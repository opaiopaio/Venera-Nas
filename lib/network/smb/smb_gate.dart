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
/// - **`reset()` / `forceReset()`**：把当前持有者登记为 **zombie** ✓（它们可能仍在
///   原生层握手/读文件 ✓，不能当成"已经结束" ✗），并让所有等待者按 `null` 失败 ✓
///   （调用方据此走可重试错误 ✓）；**zombie 的 `release` 到达前不发放任何新名额** ✓
///   —— 否则 `reset()` 后新的 `Smb2Pool.connect` 会与仍在握手的旧 connect 真并发 ✗
///   （libsmb2 的 `active_contexts` 无锁 ⇒ `0xc0000005` ✓）。
/// - **`capacity > 1`**：最多同时 [capacity] 个持有者 ✓；其余排队 ✓。
/// - **统计/看门狗**：[inUse] **活跃**占用数 ✓、[resetPendingCount] 已复位待归还数 ✓；
///   [earliestAcquiredAt] 取**两者中最早**的占用时间 ✓（供 `hasBeenLockedFor` 判断锁是否卡死 ✓）。
class SmbGate {
  SmbGate({this.capacity = 1}) : assert(capacity > 0, 'capacity 必须 ≥ 1');

  /// 并发名额数 ✓（1 = 串行 ✓；>1 = 有界并发 ✓）。
  final int capacity;

  /// 当前持有者：所有权标记 → 授予时间 ✓。
  ///
  /// `Map` 保持插入顺序 ✓（释放后重新授予的凭证会排到末尾 ✓）；但"最早占用"
  /// 现在由 [earliestAcquiredAt] **真正比较时间**得出 ✓（还要把 zombie 一起算上 ✓），
  /// 不再依赖 `values.first` ✗。
  final Map<Object, DateTime> _holders = {};

  /// ⭐ 2026-10-26：**被 `reset()` 剥离、但原生操作可能仍在跑**的持有者 ✓
  /// （所有权标记 → 原授予时间 ✓；保留时间戳是为了让看门狗与统计仍能看见它 ✓）。
  ///
  /// 为什么单列一张表 ✗→✓：`reset()` 若只清 `_holders` ✓，闸门会立刻放行新请求 ✗，
  /// 而旧持有者的 `Smb2Pool.connect` 可能还在原生层握手 ⇒ **两个 connect 真并发** ✗
  /// （libsmb2 的 `active_contexts` 无锁 ⇒ `0xc0000005` ✓）。
  /// 现在旧的 owner 留在这里当 **zombie** ✓：它的 `release()` 到达前，新的 `acquire()`
  /// 一律继续排队 ✓；`release()` 到达后清掉 zombie ✓，被阻塞的请求才依次获得名额 ✓。
  /// ⚠️ 用 `Map` 而不是 `Set` ✓：必须记住它们**开始占用**的时间 ✓，否则 `reset()` 后
  /// [earliestAcquiredAt] 会瞬间变 `null` ⇒ 看门狗误判"已空闲" ✗（统计失真 ✓）。
  final Map<Object, DateTime> _zombies = {};

  /// 等待队列 ✓（高优先级先出队 ✓）。
  final List<Completer<SmbGateTicket?>> _high = [];

  final List<Completer<SmbGateTicket?>> _low = [];

  /// 是否还有名额被占用 ✓（容量 > 1 时表示"至少一个"✓）。
  ///
  /// ⚠️ 包含 zombie ✓ —— 对调用方来说"原生操作可能还在跑"就等同于**不能并发** ✗
  /// （`closeSharedSmbClient` 等据此决定"现在断开安不安全" ✓）。
  bool get locked => _holders.isNotEmpty || _zombies.isNotEmpty;

  /// 当前**活跃**占用数 ✓（**不含**已复位待归还的 zombie ✓，它们见 [resetPendingCount] ✓）。
  int get inUse => _holders.length;

  /// 当前排队等待数 ✓（统计用 ✓）。
  int get waiting => _high.length + _low.length;

  /// 被 `reset()` 剥离、原生操作**尚未归还**的持有者数 ✓（统计/排查用 ✓）。
  ///
  /// ⭐ 与 [inUse] 分开统计 ✓：`inUse == 0 && resetPendingCount > 0` 表示
  /// "闸门已复位、但旧原生操作可能还在跑" ✓ —— 此时 [locked] 仍为 true ✓，
  /// **绝不能**放行新的原生操作 ✗。
  int get resetPendingCount => _zombies.length;

  /// 最早一次**仍未归还**的原生操作开始时间 ✓；全部空闲时为 `null` ✓。
  ///
  /// ⚠️ 活跃持有者与"已复位待归还"（zombie ✓）**一起参与比较** ✗→✓：
  /// `reset()` 后 `_holders` 已空，但原生操作可能仍在跑 ✓；若不算 zombie，
  /// 这里会在复位瞬间变 `null` ⇒ [hasBeenLockedFor] 误判"已空闲" ✗
  /// （这正是"reset 后统计失真"的根因 ✓）。
  DateTime? get earliestAcquiredAt {
    DateTime? earliest;
    for (final at in _holders.values) {
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    for (final at in _zombies.values) {
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    return earliest;
  }

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
    // ⚠️ `_zombies` 非空时**即使有空位也不发** ✗ —— 空位是 `reset()` 强行"制造"的 ✓，
    // 那份原生操作可能仍在跑 ✓；必须等它 `release()` 后才真正可用 ✓。
    if (_holders.length < capacity && _zombies.isEmpty) {
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
  ///
  /// ⚠️ `reset()` 剥离的 **zombie** 也认这张凭证 ✓：收到它的 `release()` 会清掉
  /// zombie 并唤醒排队者 ✓，但返回 `false`（它没有释放任何**当前持有者**的名额 ✓，
  /// 与旧语义/既有调用方兼容 ✓）。
  bool release(SmbGateTicket ticket) {
    if (ticket._released) {
      return false;
    }
    if (_zombies.remove(ticket._owner) != null) {
      // 原生操作终于结束 ⇒ 可以安全放行新请求了 ✓。
      ticket._released = true;
      _grantNext();
      return false;
    }
    if (!_holders.containsKey(ticket._owner)) {
      return false;
    }
    ticket._released = true;
    _holders.remove(ticket._owner);
    _grantNext();
    return true;
  }

  /// ⚠️ 强制复位 ✓：把当前持有者全部登记为 **zombie** ✓（不直接消失 ✗），
  /// 并让所有等待者按 `null` 返回 ✓ ⇒ 调用方走可重试错误 ✓。
  ///
  /// 为什么不直接清空 ✓：`reset()` 被用来"自愈卡死"✓，但持有者可能是**仍在原生
  /// 握手的 connect** ✓ —— 若把它当空气放行新 connect ✗，就是 libsmb2 的并发崩溃
  /// 路径 ✓。zombie 的 `release()` 到达前，[acquire] 继续排队 ✓；到达后恢复 ✓。
  void reset() {
    // ⭐ 连**原授予时间**一起搬进 zombie 表 ✓ —— 统计/看门狗仍能看见这次"仍未归还"的占用 ✓
    //（只搬 owner 不搬时间 ⇒ `earliestAcquiredAt` 复位后变 null ⇒ 看门狗失真 ✗）。
    _zombies.addAll(_holders);
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
    // ⚠️ zombie 未清空前绝不发放 ✗（见 `_zombies` 的注释 ✓）。
    if (_zombies.isNotEmpty) {
      return;
    }
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
