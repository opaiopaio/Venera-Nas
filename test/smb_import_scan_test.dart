import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/utils/import_comic.dart';

/// SMB 导入的「进度 / 取消」纯逻辑测试 ✓（2026-10-24 目标轮 6 ✓）
///
/// 守护点：
/// 1. 进度回调序列正确（`(0,total)` 起步 ✓ 每检查完一个目录 +1 ✓）
/// 2. 无效目录（`checkOne` 返回 null）**不进结果** ✓
/// 3. 取消后**立即停止** ✓ 且返回 `false`（调用方据此**不落库** ✓）
/// 4. 一开始就被取消 ⇒ **一个目录都不检查** ✓
void main() {
  test('进度序列与结果收集', () async {
    final progress = <(int, int)>[];
    final results = <String>[];

    final completed = await ImportComic.scanSmbDirectories<String>(
      directoryPaths: ['a', 'b', 'c'],
      checkOne: (path) async => path == 'b' ? null : 'comic-$path',
      results: results,
      onProgress: (current, total) => progress.add((current, total)),
    );

    expect(completed, isTrue);
    expect(results, ['comic-a', 'comic-c'], reason: 'null 结果必须被跳过');
    expect(progress, [(0, 3), (1, 3), (2, 3), (3, 3)]);
  });

  test('中途取消 ⇒ 立即停止并返回 false', () async {
    var calls = 0;
    var cancel = false;
    final results = <String>[];

    final completed = await ImportComic.scanSmbDirectories<String>(
      directoryPaths: ['a', 'b', 'c'],
      checkOne: (path) async {
        calls++;
        // 第一个目录处理完就请求取消（模拟用户点了 Cancel ✓）
        cancel = true;
        return 'comic-$path';
      },
      results: results,
      isCancelled: () => cancel,
    );

    expect(completed, isFalse, reason: '取消必须让调用方知道，不能落库');
    expect(calls, 1, reason: '取消后不应再检查后续目录');
    expect(results, ['comic-a']);
  });

  test('一开始就取消 ⇒ 不检查任何目录', () async {
    var calls = 0;
    final completed = await ImportComic.scanSmbDirectories<String>(
      directoryPaths: ['a', 'b'],
      checkOne: (path) async {
        calls++;
        return path;
      },
      results: <String>[],
      isCancelled: () => true,
    );

    expect(completed, isFalse);
    expect(calls, 0);
  });

  test('空目录列表 ⇒ 正常完成，只有 (0,0) 进度', () async {
    final progress = <(int, int)>[];
    final completed = await ImportComic.scanSmbDirectories<String>(
      directoryPaths: const [],
      checkOne: (path) async => path,
      results: <String>[],
      onProgress: (current, total) => progress.add((current, total)),
    );

    expect(completed, isTrue);
    expect(progress, [(0, 0)]);
  });

  test('不传回调也能正常工作（null 安全）', () async {
    final results = <String>[];
    final completed = await ImportComic.scanSmbDirectories<String>(
      directoryPaths: ['a', 'b'],
      checkOne: (path) async => path,
      results: results,
    );
    expect(completed, isTrue);
    expect(results, ['a', 'b']);
  });
}
