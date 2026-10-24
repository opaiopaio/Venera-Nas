import 'dart:async';

/// SMB 闸门的**持有凭证** ✓。
///
/// 只有拿到凭证的调用方才允许 `release(ticket)` ✓；凭证被释放、被
/// [SmbGate.forceReset] 清掉、或已换给下一个持有者之后都会失效 ✓ ——
/// 这样"迟到的 `release()`"不会误解锁别人正持有的名额 ✗
///（容量 > 1 时同样成立：每个名额各有一张凭证 ✓）。
class SmbGateTicket {
  SmbGateTicket._(this._owner);

  /// 所有权标记（每次授予都是新对象 ✓，用 identity 比较 ✓）。
  final Object _owner;

  bool _released = false;

  bool get isReleased => _released;
}

/// ⭐ SMB 原生操作的**可复用闸门** ✓ —— 由 `SmbSerial`（全局容量 1 ✓）与
/// 阅读器读图（容量 2 ✓）共用 ✓；只是把"排队/优先级/超时/复位/凭证"抽成一份 ✓，
/// 业务语义不变 ✓。
///
/// ## 为什么 SMB 需要闸门（有实证 ✓）
/// Windows 事件日志记录过 `libsmb2.dll` 的 **0xc0000005 访问冲突** ✓ ——
/// 原生 SMB 库不能在并发使用 / 读到一半被 disconnect ✓；所以原生操作必须排队 ✓。
///
/// ## 约定
/// - **优先级**：`high: true`（用户在等 ✓）先出队；`low`（预取/后台 ✓）让路 ✓。
/// - **凭证所有权**：`acquire` 返回 [SmbGateTicket]；`release` 只接受**当前持有**的
///   凭证 ✓ —— 超时后迟到释放、`reset()` 后旧凭证、重复释放都不会误解锁新人 ✗。
/// - **等待超时**：由 `Timer + isCompleted` 互斥判定 ✓（不用 `future.timeout` ✗，
///   否则存在"超时返回 null 的同时名额刚移交给它"的竞态 ⇒ 名额永久丢失 ✗）；
///   超时返回 `null` ✓，**不抛异常** ✓。
/// - **`reset()` / `forceReset()`**：直接清空持有者，并让所有等待者按 `null` 失败 ✓
///   （调用方据此走可重试错误 ✓）。
/// - **`capacity > 1`**：最多同时 [capacity] 个持有者 ✓；其余排队 ✓。
/// - **统计/看门狗**：[inUse] 当前占用数 ✓；[earliestAcquiredAt] 最早占用时间 ✓
///   （供 `hasBeenLockedFor` 判断锁是否卡死 ✓）。
class SmbGate {
  SmbGate({this.capacity = 1}) : assert(capacity > 0, 'capacity 必须 ≥ 1');

  /// 并发名额数 ✓（1 = 串行 ✓；>1 = 有界并发 ✓）。
  final int capacity;

  /// 当前持有者：所有权标记 → 授予时间 ✓。
  ///
  /// Dart 的 `Map` 保持插入顺序 ✓ ⇒ `values.first` 就是**最早**的占用时间 ✓
  /// （释放后重新授予的凭证会排到末尾 ✓，不会把"最早"算成已经释放的那次 ✓）。
  final Map<Object, DateTime> _holders = {};

  /// 等待队列 ✓（高优先级先出队 ✓）。
  final List<Completer<SmbGateTicket?>> _high = [];

  final List<Completer<SmbGateTicket?>> _low = [];

  /// 是否还有名额被占用 ✓（容量 > 1 时表示"至少一个"✓）。
  bool get locked => _holders.isNotEmpty;

  /// 当前占用数 ✓（统计/看门狗用 ✓）。
  int get inUse => _holders.length;

  /// 当前排队等待数 ✓（统计用 ✓）。
  int get waiting => _high.length + _low.length;

  /// 最早一次**仍在持有**的占用时间 ✓；空闲时为 `null` ✓。
  DateTime? get earliestAcquiredAt =>
      _holders.isEmpty ? null : _holders.values.first;

  /// 占用是否已超过 [limit] ✓（供看门狗决定是否 `reset()` ✓）。
  bool hasBeenLockedFor(Duration limit) {
    final at = earliestAcquiredAt;
    return at != null && DateTime.now().difference(at) > limit;
  }

  /// 抢一个名额 ✓。返回凭证 = 拿到（**必须** `release(ticket)` ✓）；
  /// `null` = 等待超时放弃 ✓（或等待期间被 `reset()` 放掉 ✓）。
  ///
  /// ⚠️ 超时判定用 **Timer + `isCompleted` 互斥**（不要用 `future.timeout`）✗ ——
  /// 后者存在竞态：超时返回 `null` 的同时 `release()` 可能刚把名额移交给我们 ✓
  /// ⇒ 名额丢失 ⇒ 锁永久 locked ✗（复查曾指出这一条 ✓）。
  Future<SmbGateTicket?> acquire({
    required bool high,
    Duration? timeout,
  }) async {
    if (_holders.length < capacity) {
      return _grant();
    }
    final c = Completer<SmbGateTicket?>();
    final queue = high ? _high : _low;
    queue.add(c);
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        // 与 `release` 在同一事件循环里互斥 ✓：要么这里先超时出队 ✓，
        // 要么 `_grantNext` 先把它完成 ✓，两者不会都成立 ✓。
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

  /// 释放凭证对应的名额 ✓。返回 `false` = 凭证已失效（不是当前持有者）✓。
  ///
  /// 用所有权校验替代裸 `release()` ✓：迟到的释放（超时/被 `reset`/重复 release）
  /// 不能把**后来者**的名额放掉 ✗。
  bool release(SmbGateTicket ticket) {
    if (ticket._released || !_holders.containsKey(ticket._owner)) {
      return false;
    }
    ticket._released = true;
    _holders.remove(ticket._owner);
    _grantNext();
    return true;
  }

  /// ⚠️ 强制复位 ✓：放掉所有持有者与等待者（等待者按 `null` 返回 ✓ ⇒ 调用方走可重试错误 ✓）。
  ///
  /// 同时清空持有者 ✓ ⇒ 旧 ticket 立即失效 ✓，迟到的 `release(ticket)`
  /// 不会误解锁复位后新拿到的名额 ✓。
  void reset() {
    _holders.clear();
    final waiters = [..._high, ..._low];
    _high.clear();
    _low.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete(null);
      }
    }
  }

  /// [reset] 的别名 ✓ —— 保留"强制复位"的语义名称 ✓（调用方不必区分 ✓）。
  void forceReset() => reset();

  /// 直接授予一个名额 ✓（调用方已确认有空位 ✓）。
  SmbGateTicket _grant() {
    final ticket = SmbGateTicket._(Object());
    _holders[ticket._owner] = DateTime.now();
    return ticket;
  }

  /// 把腾出的名额移交给下一个等待者 ✓（高优先级队列优先 ✓）。
  ///
  /// 用 `while` 而不是单次移交 ✓：容量 > 1 时若同时腾出多个名额（或队列里
  /// 已有被完成/超时的残留 ✓），都会在同一轮补齐 ✓。
  void _grantNext() {
    while (_holders.length < capacity) {
      final queue = _high.isNotEmpty ? _high : _low;
      if (queue.isEmpty) {
        return;
      }
      final next = queue.removeAt(0);
      if (next.isCompleted) {
        // 理论上不会发生（超时会先从队列移除 ✓）；防御性跳过保持队列推进 ✓。
        continue;
      }
      next.complete(_grant());
    }
  }
}
