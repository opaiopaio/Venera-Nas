import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_serial.dart';

/// SMB 全局串行闸门的专项测试 ✓（2026-10-24 目标轮 4 ✓）
///
/// 为什么要有（都是真实踩过的坑 ✓）：
/// 1. 闸门必须**真正串行** ✓ —— libsmb2 并发会原生崩溃（`0xc0000005` ✓）
/// 2. `run()` 抛异常时**必须释放锁** ✓ —— 否则后续所有 SMB 操作永久卡死 ✗
/// 3. 超时**不能泄漏名额** ✓ —— 曾因 `future.timeout` 竞态导致锁永久 locked ✗
/// 4. **前台优先** ✓ —— 当前页读图不能被后台预取/封面堵住 ✗
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
    await SmbSerial.acquire(high: false);

    final order = <String>[];
    final low = SmbSerial.run(() async => order.add('low'), high: false);
    final high = SmbSerial.run(() async => order.add('high'), high: true);
    // 等两者都进入等待队列。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    SmbSerial.release();
    await Future.wait([low, high]);

    expect(order, ['high', 'low'], reason: '用户在等的请求必须排在后台任务前面');
  });

  test('超时获取返回 false，且不会泄漏名额', () async {
    await SmbSerial.acquire(high: false);
    final granted = await SmbSerial.acquire(
      high: true,
      timeout: const Duration(milliseconds: 40),
    );
    expect(granted, isFalse);

    SmbSerial.release();
    expect(SmbSerial.locked, isFalse, reason: '超时后名额不能被吞掉');

    final again = await SmbSerial.acquire(high: false);
    expect(again, isTrue);
    SmbSerial.release();
  });

  test('reset 能强制解锁并放掉等待者', () async {
    await SmbSerial.acquire(high: false);
    final waiter = SmbSerial.acquire(
      high: true,
      timeout: const Duration(seconds: 5),
    );
    SmbSerial.reset();
    expect(await waiter, isFalse);
    expect(SmbSerial.locked, isFalse);
    final again = await SmbSerial.acquire(high: false);
    expect(again, isTrue);
    SmbSerial.release();
  });

  test('排队等待超时 ⇒ 抛可重试错误，不无限等（卡住恢复 ✓）', () async {
    await SmbSerial.acquire(high: false); // 模拟"一个卡死的操作占着锁"
    await expectLater(
      SmbSerial.run<void>(
        () async {},
        waitTimeout: const Duration(milliseconds: 150),
      ),
      throwsA(isA<String>()),
    );
    SmbSerial.release();
    // 释放后应恢复正常 ✓
    await SmbSerial.run<void>(() async {});
    expect(SmbSerial.locked, isFalse);
  });
}
