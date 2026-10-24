import 'package:venera_nas/foundation/log.dart';
import 'dart:async';

import 'smb_exception.dart';
import 'smb_gate.dart';

/// SMB 闸门的**持有凭证** ✓。
///
/// 实现已收敛到 [SmbGateTicket] ✓；本别名保留原公开类型名 ✓，调用方无需改动 ✓。
/// 只有拿到凭证的调用方才允许 [SmbSerial.release] ✓；凭证被释放、被
/// [SmbSerial.forceReset] 清掉、或已换给下一个持有者之后都会失效 ✓ ——
/// 这样"迟到的 `release()`"不会误解锁别人正持有的名额 ✗。
typedef SmbSerialTicket = SmbGateTicket;

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
///
/// ⭐ 排队/优先级/凭证/超时/复位的实现已抽到 [SmbGate] ✓（阅读器读图共用同一份 ✓）；
/// 本类只是 `SmbGate(capacity: 1)` 的**薄封装** ✓，公开 API 与语义保持不变 ✓。
class SmbSerial {
  SmbSerial._();

  /// 唯一的全局闸门 ✓：容量 1 = 同一时刻只有一个原生操作 ✓。
  static final SmbGate _gate = SmbGate(capacity: 1);

  /// 看门狗阈值 ✓ —— **`run()` 自愈逻辑的唯一判据** ✓：等待超时后，只有持有者
  /// 已被占用超过此时长才 `reset()` ✓（见 [run] ✓）。
  ///
  /// 不要在 3 秒就复位 ✗：那时原生握手可能还在跑 ✓，
  /// 复位会把仍在握手的 connect 抹掉 ⇒ 两个 `Smb2Pool.connect` 真并发 ✗
  /// （libsmb2 `active_contexts` 竞态 ⇒ `0xc0000005` ✓）。
  /// ⭐ 阅读器自己的双槽闸门**复用同一个阈值** ✓（`reader_image.dart` ✓）——
  /// 两处看门狗保持同一个数 ✓，避免改一处漏一处 ✗。
  static const Duration watchdog = Duration(seconds: 90);

  /// 闸门当前是否被占用 ✓（**含**已复位待归还的 zombie ✓ —— 它们可能仍在原生层跑 ✓）。
  static bool get locked => _gate.locked;

  /// ⚠️ 强制复位 ✓：把当前持有者降级为 **zombie**、所有等待者按失败返回 ✓
  /// ⇒ 调用方走可重试错误 ✓。
  ///
  /// ⚠️ zombie 的 `release(ticket)` 到达前**不会放行新的 `acquire`** ✓ ——
  /// 它可能仍在原生层握手/读文件 ✓，此时放行就是 libsmb2 并发崩溃路径 ✗；
  /// 到达后清 zombie ✓，排队者才依次获得名额 ✓。
  static void reset() => _gate.reset();

  /// 抢名额 ✓。返回 ticket = 拿到（**必须** `release(ticket)` ✓）；`null` = 超时放弃 ✓。
  ///
  /// ⚠️ 超时判定用 **Timer + `isCompleted` 互斥**（不要用 `future.timeout`）✗ ——
  /// 后者存在竞态：超时返回 null 的同时 `release()` 可能刚把名额移交给我们 ✓
  /// ⇒ 名额丢失 ⇒ 锁永久 locked ✗（复查曾指出这一条 ✓）。
  static Future<SmbSerialTicket?> acquire({
    required bool high,
    Duration? timeout,
  }) => _gate.acquire(high: high, timeout: timeout);

  /// 释放 ticket 对应的名额 ✓。返回 `false` = ticket 已失效（不是当前持有者）✓。
  ///
  /// 用所有权校验替代裸 `release()` ✓：迟到的释放（超时/被 forceReset/重复 release）
  /// 不能把**后来者**的锁放掉 ✗。
  static bool release(SmbSerialTicket ticket) => _gate.release(ticket);

  /// 在闸门内执行一个原生操作 ✓（最简单的用法 ✓）。
  ///
  /// [high] = true 表示"用户在等" ✓；后台任务传 false ✓。
  ///
  /// ⭐ 2026-10-25：**单次 acquire + 总超时** ✓ ——
  /// 原先每 200ms 轮询抢锁 ✗：排队久了会制造大量无意义的定时器，
  /// 且"轮询间隙"与 release 之间有额外的公平性问题 ✓。
  /// 现在由 [acquire] 内部用 Completer 排队 + 单次 Timer 超时 ✓。
  ///
  /// ⭐ 2026-10-26（P0 ✓）：**不再"等 3 秒就无条件 reset"** ✗ ——
  /// 旧实现见拿不到名额就 `reset()` ✓ ⇒ 把**仍在原生握手的 connect** 从闸门抹掉 ✗
  /// ⇒ 两个 `Smb2Pool.connect` 真并发 ⇒ libsmb2 `active_contexts` 竞态 / `0xc0000005` ✓；
  /// 同时 `waitTimeout` 形参也形同虚设 ✗。
  /// 现在：
  /// 1. 先按 [waitTimeout]（默认 20s ✓）正常排队 ✓；
  /// 2. 等待超时后**只有看门狗判定持有者已超 [watchdog]** 才 `reset()` ✓
  ///    （复位会把持有者降级为 zombie ✓，它的 `release` 到达前新请求继续排队 ✓，
  ///    绝不放行第二个原生操作 ✓）；
  /// 3. 超时仍拿不到 ⇒ 抛 `SmbException`（文案逐字不变 ✓）。
  static Future<T> run<T>(
    Future<T> Function() op, {
    bool high = false,
    Duration waitTimeout = const Duration(seconds: 20),
  }) async {
    final gateWaitStart = DateTime.now();
    var ticket = await acquire(high: high, timeout: waitTimeout);
    if (ticket == null) {
      // ⭐ 关键判断 ✓：**只看门狗超时才复位** ✗→✓。
      // `earliestAcquiredAt == null` = 本来就没持有者（比如刚被别的调用 reset 过 ✓），
      // 此时不该再 reset（那只会清空别人的等待者 ✗）。
      if (_gate.hasBeenLockedFor(watchdog)) {
        final acquiredAt = _gate.earliestAcquiredAt;
        final holderAge = acquiredAt == null
            ? -1
            : DateTime.now().difference(acquiredAt).inMilliseconds;
        Log.error(
          'SMB Gate',
          "watchdog timeout: reset, holderAge=${holderAge}ms, "
              "waited=${DateTime.now().difference(gateWaitStart).inMilliseconds}ms",
        );
        reset();
        // 复位后不假设"名额立刻可用" ✓ —— 被剥离的持有者仍是 zombie ✓，
        // 只有它的 release 到达才会放行 ✓。把剩余预算交给 acquire 继续等 ✓。
        final waited = DateTime.now().difference(gateWaitStart);
        final remaining = waitTimeout - waited;
        ticket = await acquire(
          high: high,
          timeout: remaining.isNegative ? Duration.zero : remaining,
        );
      }
    }
    if (ticket == null) {
      // ⭐ 2026-10-26：SMB 层异常改为类型化 ✓ —— 文案保持逐字不变 ✓
      //（上层直接 `toString()` 展示，用户可见内容不变 ✓）。
      throw const SmbException(
        "SMB 操作等待超时（服务器可能无响应）。"
        "可到「设置 → 网络 → SMB 服务器」点「重置 SMB 连接」后重试。",
      );
    }
    try {
      final waited = DateTime.now().difference(gateWaitStart);
      if (waited.inMilliseconds > 200) {
        Log.info(
          'SMB Gate',
          'acquired after ${waited.inMilliseconds}ms (high=$high)',
        );
      }
      final opStart = DateTime.now();
      final result = await op();
      final used = DateTime.now().difference(opStart);
      if (used.inMilliseconds > 1000) {
        Log.info('SMB Gate', 'op took ${used.inMilliseconds}ms');
      }
      return result;
    } finally {
      release(ticket);
    }
  }

  /// ⭐ 2026-10-25：**强制重置闸门** ✓ —— 供"重置 SMB 连接"按钮用 ✓
  ///（把当前持有者降级为 zombie、所有等待者按失败返回 ✓）；
  /// ⚠️ zombie 的 `release()` 到达前不会放行新请求 ✓（防原生并发 ✓），
  /// 调用方还应同时断开复用的连接 ✓。
  static void forceReset() => reset();
}
