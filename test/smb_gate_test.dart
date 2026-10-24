import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_gate.dart';

/// 通用 SMB 闸门（[SmbGate]）的专项测试 ✓。
///
/// 覆盖两套旧实现（`SmbSerial` 单槽 / 阅读器双槽）合并后必须保持的行为 ✓：
/// 1. **优先级**：高优先级（用户在等 ✓）先于低优先级（预取 ✓）出队 ✓
/// 2. **容量**：`capacity: 2` 时可同时两个持有者 ✓，第三个必须排队 ✓
/// 3. **凭证所有权**：迟到/重复的 release 不能误解锁后来者 ✓
/// 4. **reset**：放掉所有等待者（返回 null ✓），旧凭证立即失效 ✓
/// 5. **等待超时**：超时返回 null ✓，且不泄漏名额 ✓
/// 6. **统计**：活跃占用数 / 已复位待归还数（zombie ✓）/ 最早占用时间 ✓
///    （看门狗判断依赖它 ✓；reset 后不能把 zombie 当空闲 ✗）
///
/// 每个用例都自建独立 [SmbGate] 实例 ✓ —— 不依赖全局状态 ✓（避免全量跑时互相污染 ✗）。
void main() {
  test('capacity: 2 时可同时两个持有者，第三个排队并在超时后返回 null', () async {
    final gate = SmbGate(capacity: 2);

    final first = await gate.acquire(high: true);
    final second = await gate.acquire(high: true);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(gate.locked, isTrue);
    expect(gate.inUse, 2);

    final third = await gate.acquire(
      high: true,
      timeout: const Duration(milliseconds: 20),
    );
    expect(third, isNull, reason: '两个名额都在占用时，第三个只能等到超时');

    expect(gate.release(first!), isTrue);
    expect(gate.release(second!), isTrue);
    expect(gate.locked, isFalse);
    expect(gate.inUse, 0);
  });

  test('高优先级先于低优先级出队', () async {
    final gate = SmbGate();
    final holder = await gate.acquire(high: false);
    expect(holder, isNotNull);

    // 先排低优先级，再排高优先级 ✓ —— 出队顺序必须反过来 ✓。
    // acquire 在第一个 await 前会同步入队 ✓，所以这里无需额外等待 ✓。
    final low = gate.acquire(high: false, timeout: const Duration(seconds: 2));
    final high = gate.acquire(high: true, timeout: const Duration(seconds: 2));

    expect(gate.release(holder!), isTrue);

    final highTicket = await high;
    expect(highTicket, isNotNull, reason: '高优先级必须第一个被移交名额');
    // 高优先级释放后才轮到低优先级（若实现按 FIFO，则 high 会超时返回 null ✓）。
    expect(gate.release(highTicket!), isTrue);

    final lowTicket = await low;
    expect(lowTicket, isNotNull);
    expect(gate.release(lowTicket!), isTrue);
    expect(gate.locked, isFalse);
  });

  test('迟到 release 不误放后来者的名额', () async {
    final gate = SmbGate(capacity: 2);
    final first = await gate.acquire(high: true);
    final second = await gate.acquire(high: true);
    expect(first, isNotNull);
    expect(second, isNotNull);

    // 释放一个名额后，新来的调用方立刻拿到它 ✓。
    expect(gate.release(first!), isTrue);
    final third = await gate.acquire(high: false);
    expect(third, isNotNull);
    expect(gate.inUse, 2);

    // 用已释放的旧凭证再释放：不能把 third 的名额放掉 ✓。
    expect(gate.release(first), isFalse);
    expect(gate.inUse, 2, reason: '旧凭证失效，不得影响新持有者');
    expect(gate.locked, isTrue);

    expect(gate.release(second!), isTrue);
    expect(gate.release(third!), isTrue);
    expect(gate.locked, isFalse);
  });

  test('reset 把持有者降级为 zombie：释放前不放行新 acquire', () async {
    final gate = SmbGate();
    final holder = await gate.acquire(high: false);
    expect(holder, isNotNull);

    final highWaiter = gate.acquire(
      high: true,
      timeout: const Duration(seconds: 5),
    );
    final lowWaiter = gate.acquire(
      high: false,
      timeout: const Duration(seconds: 5),
    );
    await Future<void>.delayed(Duration.zero);
    expect(gate.waiting, 2);

    // 让"占用时间"与 reset 之间至少跨 1ms ✓：后面对 `hasBeenLockedFor(Duration.zero)` 的断言
    // 依赖它 ✓（同一毫秒内差值为 0，断言会假红 ✗）。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final acquiredAt = gate.earliestAcquiredAt;
    gate.reset();
    expect(await highWaiter, isNull, reason: 'reset 后等待者按失败返回');
    expect(await lowWaiter, isNull);
    expect(gate.inUse, 0);
    expect(gate.locked, isTrue, reason: '被剥离的持有者仍是 zombie：原生操作可能还在跑，不能当成空闲');
    // ⭐ 统计必须区分"活跃"与"已复位待归还" ✓（reset 后 inUse=0 但不等于空闲 ✓）。
    expect(gate.resetPendingCount, 1);
    expect(
      gate.earliestAcquiredAt,
      acquiredAt,
      reason: 'zombie 的占用时间必须保留，否则看门狗误判空闲',
    );
    expect(
      gate.hasBeenLockedFor(Duration.zero),
      isTrue,
      reason: '复位后看门狗仍需看见 zombie 的占用',
    );

    // ⭐ P0 关键断言：zombie 的 release 到达前，**新请求一律不能拿到名额** ✗
    final blocked = await gate.acquire(
      high: true,
      timeout: const Duration(milliseconds: 20),
    );
    expect(blocked, isNull, reason: 'zombie 未释放前不得放行第二个原生操作');

    // release(zombie) 只清理 zombie（返回 false = 没释放任何"当前持有者"的名额），
    // 之后才允许新请求 ✓。
    expect(gate.release(holder!), isFalse);
    expect(gate.resetPendingCount, 0);
    expect(gate.earliestAcquiredAt, isNull);
    expect(gate.hasBeenLockedFor(Duration.zero), isFalse);
    expect(gate.locked, isFalse);

    final next = await gate.acquire(high: true);
    expect(next, isNotNull);
    expect(gate.release(holder), isFalse);
    expect(gate.locked, isTrue);
    expect(gate.release(next!), isTrue);
    expect(gate.locked, isFalse);
  });

  test('复位期间不出现两个持有者同时存在（容量 1）', () async {
    final gate = SmbGate();
    final holder = await gate.acquire(high: false);
    expect(holder, isNotNull);

    // 先把一个请求排进队列，再 reset：它按 null 失败 ✓。
    final beforeReset = gate.acquire(
      high: true,
      timeout: const Duration(seconds: 1),
    );
    await Future<void>.delayed(Duration.zero);
    gate.reset();
    expect(await beforeReset, isNull);

    // reset 之后的新请求必须继续等 zombie ✓（不能出现第二个持有者）。
    final afterReset = gate.acquire(
      high: true,
      timeout: const Duration(milliseconds: 30),
    );
    final second = await afterReset;
    expect(second, isNull);
    expect(gate.inUse, 0, reason: '复位期间绝不能同时有两个持有者');

    expect(gate.release(holder!), isFalse); // 清 zombie
    final next = await gate.acquire(high: true);
    expect(next, isNotNull);
    expect(gate.inUse, 1);
    expect(gate.release(next!), isTrue);
  });

  test('等待超时返回 null，不抛异常且不泄漏名额', () async {
    final gate = SmbGate();
    final holder = await gate.acquire(high: false);
    expect(holder, isNotNull);

    final timedOut = await gate.acquire(
      high: true,
      timeout: const Duration(milliseconds: 20),
    );
    expect(timedOut, isNull);
    expect(gate.waiting, 0, reason: '超时后必须从等待队列移除');

    expect(gate.release(holder!), isTrue);
    expect(gate.locked, isFalse, reason: '超时后名额不能被吞掉');

    final again = await gate.acquire(high: false);
    expect(again, isNotNull);
    expect(gate.release(again!), isTrue);
  });

  test('统计信息：占用数、最早占用时间与看门狗判断', () async {
    final gate = SmbGate(capacity: 2);
    expect(gate.inUse, 0);
    expect(gate.earliestAcquiredAt, isNull);
    expect(gate.hasBeenLockedFor(Duration.zero), isFalse);

    final first = await gate.acquire(high: true);
    final firstAt = gate.earliestAcquiredAt;
    expect(first, isNotNull);
    expect(firstAt, isNotNull);
    expect(gate.inUse, 1);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = await gate.acquire(high: false);
    expect(second, isNotNull);
    expect(gate.inUse, 2);
    expect(gate.earliestAcquiredAt, firstAt, reason: '最早占用时间不随后续授予而变化');
    expect(gate.hasBeenLockedFor(const Duration(milliseconds: 1)), isTrue);

    expect(gate.release(first!), isTrue);
    expect(gate.inUse, 1);
    expect(gate.earliestAcquiredAt, isNotNull);
    expect(gate.release(second!), isTrue);
    expect(gate.earliestAcquiredAt, isNull);
  });
}
