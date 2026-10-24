import 'dart:async';

/// SMB 闸门的**持有凭证** ✓。
///
/// 只有拿到凭证的调用方才允许 [SmbSerial.release] ✓；凭证被释放、被
/// [SmbSerial.forceReset] 清掉、或已换给下一个持有者之后都会失效 ✓ ——
/// 这样"迟到的 `release()`"不会误解锁别人正持有的名额 ✗。
class SmbSerialTicket {
  SmbSerialTicket._(this._owner);

  /// 所有权标记（每次授予都是新对象 ✓，用 identity 比较 ✓）。
  final Object _owner;

  bool _released = false;

  bool get isReleased => _released;
}

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

  /// 当前持有者的所有权标记 ✓；`null` = 空闲。
  static Object? _owner;

  /// 当前持锁开始时间 ✓ —— 看门狗用 ✓。
  static DateTime? _lockedAt;

  static final List<Completer<SmbSerialTicket?>> _high = [];

  static final List<Completer<SmbSerialTicket?>> _low = [];

  /// 看门狗阈值 ✓：持锁超过此时长 ⇒ 强制复位 ✓
  ///（异常情况下锁卡死会让所有 SMB 操作永久挂起 ✗ —— 用户只能重启 App ✗）。
  static const Duration watchdog = Duration(seconds: 90);

  static bool get locked => _owner != null;

  static bool _hasBeenLockedTooLong() {
    final at = _lockedAt;
    return _owner != null &&
        at != null &&
        DateTime.now().difference(at) > watchdog;
  }

  /// ⚠️ 强制复位 ✓：放掉锁与所有等待者（等待者按失败返回 ✓ ⇒ 调用方走可重试错误 ✓）。
  ///
  /// 同时清空当前 owner ✓ ⇒ 旧 ticket 立即失效 ✓，迟到的 `release(ticket)`
  /// 不会误解锁复位后新拿到的名额 ✓。
  static void reset() {
    _owner = null;
    _lockedAt = null;
    final waiters = [..._high, ..._low];
    _high.clear();
    _low.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete(null);
      }
    }
  }

  /// 抢名额 ✓。返回 ticket = 拿到（**必须** `release(ticket)` ✓）；`null` = 超时放弃 ✓。
  ///
  /// ⚠️ 超时判定用 **Timer + `isCompleted` 互斥**（不要用 `future.timeout`）✗ ——
  /// 后者存在竞态：超时返回 null 的同时 `release()` 可能刚把名额移交给我们 ✓
  /// ⇒ 名额丢失 ⇒ 锁永久 locked ✗（复查曾指出这一条 ✓）。
  static Future<SmbSerialTicket?> acquire({
    required bool high,
    Duration? timeout,
  }) async {
    if (_owner == null) {
      final ticket = SmbSerialTicket._(Object());
      _owner = ticket._owner;
      _lockedAt = DateTime.now();
      return ticket;
    }
    final c = Completer<SmbSerialTicket?>();
    final queue = high ? _high : _low;
    queue.add(c);
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!c.isCompleted) {
          queue.remove(c);
          c.complete(null);
        }
      });
    }
    final ticket = await c.future;
    timer?.cancel();
    return ticket;
  }

  /// 释放 ticket 对应的名额 ✓。返回 `false` = ticket 已失效（不是当前持有者）✓。
  ///
  /// 用所有权校验替代裸 `release()` ✓：迟到的释放（超时/被 forceReset/重复 release）
  /// 不能把**后来者**的锁放掉 ✗。
  static bool release(SmbSerialTicket ticket) {
    if (ticket._released || !identical(ticket._owner, _owner)) {
      return false;
    }
    ticket._released = true;
    _owner = null;
    _lockedAt = null;
    _grantNext();
    return true;
  }

  /// 把名额移交给下一个等待者 ✓（高优先级队列优先 ✓）。
  static void _grantNext() {
    final queue = _high.isNotEmpty ? _high : _low;
    if (queue.isEmpty) {
      return;
    }
    final next = queue.removeAt(0);
    if (next.isCompleted) {
      // 理论上不会发生（超时会先从队列移除 ✓）；防御性递归保持队列推进 ✓。
      _grantNext();
      return;
    }
    final ticket = SmbSerialTicket._(Object());
    _owner = ticket._owner;
    _lockedAt = DateTime.now();
    next.complete(ticket);
  }

  /// 在闸门内执行一个原生操作 ✓（最简单的用法 ✓）。
  ///
  /// [high] = true 表示"用户在等" ✓；后台任务传 false ✓。
  ///
  /// ⭐ 2026-10-25：**单次 acquire + 总超时** ✓ ——
  /// 原先每 200ms 轮询抢锁 ✗：排队久了会制造大量无意义的定时器，
  /// 且"轮询间隙"与 release 之间有额外的公平性问题 ✓。
  /// 现在由 [acquire] 内部用 Completer 排队 + 单次 Timer 超时 ✓。
  static Future<T> run<T>(
    Future<T> Function() op, {
    bool high = false,
    Duration waitTimeout = const Duration(seconds: 20),
  }) async {
    // 看门狗：锁被异常占用太久 ⇒ 先强制复位 ✓（避免永久卡死 ✗）。
    if (_hasBeenLockedTooLong()) {
      reset();
    }
    final ticket = await acquire(high: high, timeout: waitTimeout);
    if (ticket == null) {
      throw "SMB 操作等待超时（服务器可能无响应）。"
          "可到「设置 → 网络 → SMB 服务器」点「重置 SMB 连接」后重试。";
    }
    try {
      return await op();
    } finally {
      release(ticket);
    }
  }

  /// ⭐ 2026-10-25：**强制重置闸门** ✓ —— 供"重置 SMB 连接"按钮用 ✓
  ///（把卡住的锁放掉、所有等待者按失败返回 ✓）；调用方还应同时断开复用的连接 ✓。
  static void forceReset() => reset();
}
