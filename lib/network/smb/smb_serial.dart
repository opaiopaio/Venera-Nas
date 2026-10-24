import 'dart:async';

import 'package:venera_nas/foundation/design_tokens.dart';

/// ⭐ 2026-10-24：**SMB 原生操作的全局串行闸门** ✓
///
/// ## 为什么需要（有实证 ✓）
/// Windows 事件日志记录过 `libsmb2.dll` 的 **0xc0000005 访问冲突** ✓ ——
/// 原生 SMB 库**不能被并发使用**（同一连接并发读 / 读到一半被 disconnect ✓）✗。
/// 之前只在"阅读器读图"那条路上加了锁 ✓，但 `local.dart`（切章列目录）、封面加载、
/// 下载器、导入器都会各自 `new SmbClient()` **绕过那把锁** ✗ ⇒ 仍可能并发 ⇒ 仍可能崩 ✗。
///
/// ## 做法
/// 把闸门**放在 `SmbClient` 层** ✓：所有原生调用（connect / read / list / write / stat / disconnect）
/// 都必须经过这里 ✓ ⇒ 无论谁调用，同一时刻**只有一个原生操作在跑** ✓。
///
/// ## 优先级
/// - `high: true` = 用户在等（当前页读图 ✓、界面刚打开的列目录 ✓）
/// - `high: false` = 后台任务（预取、封面、下载 ✓）—— 等不到就让路 ✓，绝不堵前台 ✗
class SmbSerial {
  SmbSerial._();

  static bool _locked = false;

  /// 当前持锁开始时间 ✓ —— 看门狗用 ✓。
  static DateTime? _lockedAt;

  static final List<Completer<bool>> _high = [];

  static final List<Completer<bool>> _low = [];

  /// 看门狗阈值 ✓：持锁超过此时长 ⇒ 强制复位 ✓
  ///（异常情况下锁卡死会让所有 SMB 操作永久挂起 ✗ —— 用户只能重启 App ✗）。
  static const Duration watchdog = Duration(seconds: 90);

  static bool get locked => _locked;

  /// 等名额时的轮询间隔 ✓（用设计令牌 ✓ —— 外观守卫禁止裸时长字面量 ✗）。
  static const Duration _pollInterval = AppMotion.short;

  static bool _hasBeenLockedTooLong() {
    final at = _lockedAt;
    return _locked && at != null && DateTime.now().difference(at) > watchdog;
  }

  /// ⚠️ 强制复位 ✓：放掉锁与所有等待者（等待者按失败返回 ✓ ⇒ 调用方走可重试错误 ✓）。
  static void reset() {
    _locked = false;
    _lockedAt = null;
    final waiters = [..._high, ..._low];
    _high.clear();
    _low.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete(false);
      }
    }
  }

  /// 抢名额 ✓。返回 `true` = 拿到（**必须** `release()` ✓）；`false` = 超时放弃 ✓。
  ///
  /// ⚠️ 超时判定用 **Timer + `isCompleted` 互斥**（不要用 `future.timeout`）✗ ——
  /// 后者存在竞态：超时返回 false 的同时 `release()` 可能刚把名额移交给我们 ✓
  /// ⇒ 名额丢失 ⇒ 锁永久 locked ✗（复查曾指出这一条 ✓）。
  static Future<bool> acquire({required bool high, Duration? timeout}) async {
    if (!_locked) {
      _locked = true;
      _lockedAt = DateTime.now();
      return true;
    }
    final c = Completer<bool>();
    final queue = high ? _high : _low;
    queue.add(c);
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!c.isCompleted) {
          queue.remove(c);
          c.complete(false);
        }
      });
    }
    final granted = await c.future;
    timer?.cancel();
    return granted;
  }

  static void release() {
    if (_high.isNotEmpty) {
      _high.removeAt(0).complete(true);
      _lockedAt = DateTime.now();
      return;
    }
    if (_low.isNotEmpty) {
      _low.removeAt(0).complete(true);
      _lockedAt = DateTime.now();
      return;
    }
    _locked = false;
    _lockedAt = null;
  }

  /// 在闸门内执行一个原生操作 ✓（最简单的用法 ✓）。
  ///
  /// [high] = true 表示"用户在等" ✓；后台任务传 false ✓。
  ///
  /// ⭐ 2026-10-25（用户实测 ✓）：**排队也要有上限** ✗ ——
  /// 之前若某个原生操作**卡死**（服务器不响应 ✓），后来的列目录 / 读图会**无限排队** ✗，
  /// 表现为"扫描一直转圈 / 打开漫画一直转圈"✗。现在：[waitTimeout] 内拿不到锁 ⇒
  /// 直接抛可重试错误 ✓（界面能提示 ✓，用户也能用「重置 SMB 连接」恢复 ✓，不必重启 App ✓）。
  static Future<T> run<T>(
    Future<T> Function() op, {
    bool high = false,
    Duration waitTimeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(waitTimeout);
    while (true) {
      // 看门狗：锁被异常占用太久 ⇒ 强制复位 ✓（避免永久卡死 ✗）。
      if (_hasBeenLockedTooLong()) {
        reset();
      }
      final granted = await acquire(high: high, timeout: _pollInterval);
      if (granted) break;
      if (DateTime.now().isAfter(deadline)) {
        throw "SMB 操作等待超时（服务器可能无响应）。"
            "可到「设置 → 网络 → SMB 服务器」点「重置 SMB 连接」后重试。";
      }
    }
    try {
      return await op();
    } finally {
      release();
    }
  }

  /// ⭐ 2026-10-25：**强制重置闸门** ✓ —— 供"重置 SMB 连接"按钮用 ✓
  ///（把卡住的锁放掉、所有等待者按失败返回 ✓）；调用方还应同时断开复用的连接 ✓。
  static void forceReset() => reset();
}
