import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_exception.dart';
import 'package:venera_nas/network/smb/smb_serial.dart';

/// SMB 全局串行闸门的专项测试 ✓（2026-10-24 目标轮 4 ✓）
///
/// 为什么要有（都是真实踩过的坑 ✓）：
/// 1. 闸门必须**真正串行** ✓ —— libsmb2 并发会原生崩溃（`0xc0000005` ✓）
/// 2. `run()` 抛异常时**必须释放锁** ✓ —— 否则后续所有 SMB 操作永久卡死 ✗
/// 3. 超时**不能泄漏名额** ✓ —— 曾因 `future.timeout` 竞态导致锁永久 locked ✗
/// 4. **前台优先** ✓ —— 当前页读图不能被后台预取/封面堵住 ✗
/// 5. **释放必须带 ticket** ✓ —— 迟到的 release 不能误解锁新的持有者 ✗
void main() {
  setUp(SmbSerial.reset);
  tearDown(SmbSerial.reset);

  test('run 执行后释放锁', () async {
    expect(SmbSerial.locked, isFalse);
    await SmbSerial.run(() async {});
    expect(SmbSerial.locked, isFalse);
  });

  test('run 抛异常也会释放锁', () async {
    await expectLater(
      SmbSerial.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(SmbSerial.locked, isFalse);
  });

  test('并发 run 不会重叠执行', () async {
    var concurrent = 0;
    var maxConcurrent = 0;
    Future<void> op() async {
      concurrent++;
      maxConcurrent = math.max(maxConcurrent, concurrent);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      concurrent--;
    }

    await Future.wait(List.generate(6, (_) => SmbSerial.run(op)));
    expect(maxConcurrent, 1, reason: '同一时刻只能有一个 SMB 原生操作');
  });

  test('高优先级先于低优先级拿到名额', () async {
    // 手动占锁，模拟"一个原生操作正在跑"。
    final holder = await SmbSerial.acquire(high: false);
    expect(holder, isNotNull);

    final order = <String>[];
    final low = SmbSerial.run(() async => order.add('low'), high: false);
    final high = SmbSerial.run(() async => order.add('high'), high: true);
    // 等两者都进入等待队列。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    SmbSerial.release(holder!);
    await Future.wait([low, high]);

    expect(order, ['high', 'low'], reason: '用户在等的请求必须排在后台任务前面');
  });

  test('超时获取返回 null，且不会泄漏名额', () async {
    final holder = await SmbSerial.acquire(high: false);
    expect(holder, isNotNull);
    final timedOut = await SmbSerial.acquire(
      high: true,
      timeout: const Duration(milliseconds: 40),
    );
    expect(timedOut, isNull);

    SmbSerial.release(holder!);
    expect(SmbSerial.locked, isFalse, reason: '超时后名额不能被吞掉');

    final again = await SmbSerial.acquire(high: false);
    expect(again, isNotNull);
    SmbSerial.release(again!);
  });

  test('reset 放掉等待者，并把持有者降级为 zombie（释放前不放行）', () async {
    final holder = await SmbSerial.acquire(high: false);
    expect(holder, isNotNull);
    final waiter = SmbSerial.acquire(
      high: true,
      timeout: const Duration(seconds: 5),
    );
    SmbSerial.reset();
    expect(await waiter, isNull);
    expect(SmbSerial.locked, isTrue, reason: '持有者被剥离后仍是 zombie：它可能还在原生握手');
    // zombie 的 release 到达前，新请求只能等到超时（不能并发）。
    final blocked = await SmbSerial.acquire(
      high: false,
      timeout: const Duration(milliseconds: 20),
    );
    expect(blocked, isNull);
    expect(SmbSerial.release(holder!), isFalse); // 清 zombie
    expect(SmbSerial.locked, isFalse);
    final again = await SmbSerial.acquire(high: false);
    expect(again, isNotNull);
    SmbSerial.release(again!);
  });

  test('等待超时 ⇒ 抛可重试错误（waitTimeout 语义恢复，不无限等）', () async {
    final holder = await SmbSerial.acquire(high: false); // 模拟"一个卡死的操作占着锁"
    expect(holder, isNotNull);
    // ⭐ 只有看门狗判定持有者超过 90s 才会 reset；这里持有者才刚开始 ⇒ **必须抛错** ✓
    await expectLater(
      SmbSerial.run<void>(
        () async {},
        waitTimeout: const Duration(milliseconds: 150),
      ),
      throwsA(isA<SmbException>()),
    );
    SmbSerial.release(holder!);
    // 释放后应恢复正常 ✓
    await SmbSerial.run<void>(() async {});
    expect(SmbSerial.locked, isFalse);
  });

  test('复位期间不出现两个 op 重叠（zombie 释放前新 op 不启动）', () async {
    final holder = await SmbSerial.acquire(high: false);
    expect(holder, isNotNull);
    // 模拟"看门狗复位"：持有者被降级为 zombie（原生操作可能仍在跑）。
    SmbSerial.reset();

    var active = 0;
    var maxActive = 0;
    final order = <String>[];
    Future<void> op(String name) async {
      active++;
      if (active > maxActive) maxActive = active;
      order.add('$name-start');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      order.add('$name-end');
      active--;
    }

    final first = SmbSerial.run(
      () => op('a'),
      waitTimeout: const Duration(seconds: 2),
    );
    final second = SmbSerial.run(
      () => op('b'),
      waitTimeout: const Duration(seconds: 2),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(order, isEmpty, reason: 'zombie 未 release 前，新的原生操作绝不能启动');

    SmbSerial.release(holder!); // 清 zombie ⇒ 放行排队者
    await Future.wait([first, second]);
    expect(maxActive, 1, reason: '复位自愈也不能让两个 SMB 原生操作重叠');
    expect(order, ['a-start', 'a-end', 'b-start', 'b-end']);
  });

  test('release 只接受当前持有者的 ticket（迟到释放不解锁新人）', () async {
    final first = await SmbSerial.acquire(high: false);
    expect(first, isNotNull);
    expect(SmbSerial.release(first!), isTrue);

    final second = await SmbSerial.acquire(high: false);
    expect(second, isNotNull);
    // 用已经释放的旧 ticket 不能把 second 的锁放掉 ✓。
    expect(SmbSerial.release(first), isFalse);
    expect(SmbSerial.locked, isTrue);
    expect(SmbSerial.release(second!), isTrue);
    expect(SmbSerial.locked, isFalse);
  });

  test('重复 release 同一个 ticket 第二次返回 false', () async {
    final ticket = await SmbSerial.acquire(high: false);
    expect(ticket, isNotNull);
    expect(SmbSerial.release(ticket!), isTrue);
    expect(SmbSerial.release(ticket), isFalse);
    expect(SmbSerial.locked, isFalse);
  });

  test('forceReset 把持有者降级为 zombie，旧 ticket 不能误解锁新人', () async {
    final ticket = await SmbSerial.acquire(high: false);
    expect(ticket, isNotNull);
    SmbSerial.forceReset();
    expect(SmbSerial.locked, isTrue, reason: 'zombie 未释放前仍视为占用');
    // zombie 的 release 只清理 zombie（返回 false = 没有释放当前持有者的名额）。
    expect(SmbSerial.release(ticket!), isFalse);
    expect(SmbSerial.locked, isFalse);

    final next = await SmbSerial.acquire(high: false);
    expect(next, isNotNull);
    expect(SmbSerial.release(ticket), isFalse);
    expect(SmbSerial.locked, isTrue);
    expect(SmbSerial.release(next!), isTrue);
  });
}
