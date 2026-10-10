import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⭐ 阅读器退出时的**历史落库**守护（2026-10-10 ✓，修 P0-7 的真回归 ✓）。
///
/// 背景（上一轮改错 ✓）：`dispose()` 里直接 `_updateHistoryTimer?.cancel()` ✗ ——
/// 但该 Timer 的回调体（`reader.dart:426-429` ✓）只有 `HistoryManager().addHistoryAsync(history!)` ✓，
/// **不读写 State、不 setState** ✓ ⇒ 取消它避免不了任何报错 ✓，只会把**尚未到期的写入丢掉** ✗：
/// 该 Timer 是 1 秒防抖 ✓（每次翻页 cancel+重启 ✓），而 `addHistoryAsync` **全仓只有这一处调用** ✓
/// ⇒ 退出阅读器时**回退到旧页码** ✗、首次阅读未落库的漫画**整条历史丢失** ✗。
///
/// ⇒ 正确形态 ✓：`dispose()` 里**先 flush（立即写一次）再 cancel** ✓。
/// 本守护用**静态结构断言**锁死它 ✓（阅读器整窗 widget 测试代价过大 ✓，这里锁顺序即可 ✓）：
/// `dispose()` 段内必须出现 `addHistoryAsync(history!)` ✓，且它在 `_updateHistoryTimer?.cancel()` **之前** ✓。
void main() {
  test('T-HIST1 dispose 必须先把历史写一次再取消防抖 Timer（否则丢数据 ✗）', () {
    final src = File('lib/pages/reader/reader.dart').readAsStringSync();
    final code = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    final disposeStart = code.indexOf('void dispose()');
    expect(disposeStart, isNot(-1), reason: '找不到 dispose（结构可能已改，请同步本守卫）');
    final disposeEnd = code.indexOf('super.dispose()', disposeStart);
    expect(disposeEnd, isNot(-1), reason: 'dispose 段未正常结束');
    final block = code.substring(disposeStart, disposeEnd);

    final flush = block.indexOf('addHistoryAsync(history!)');
    final cancel = block.indexOf('_updateHistoryTimer?.cancel()');
    expect(cancel, isNot(-1), reason: 'dispose 仍应取消防抖 Timer（避免悬挂 ✓）');
    expect(
      flush,
      isNot(-1),
      reason:
          'dispose **必须**先把历史立即写一次（flush）✓ —— 否则退出阅读器时未到期的写入被丢弃 ✗'
          '（重进回旧页码 ✓、首次阅读的漫画整条历史不落库 ✗）',
    );
    expect(flush < cancel, isTrue, reason: '必须先 flush 再 cancel ✓（顺序反了就等于没写 ✓）');
  });

  test('T-HIST2 兜底 Timer 的代次校验必须在动共享字段之前（P0-8 ✗）', () {
    final src = File('lib/pages/reader/reader.dart').readAsStringSync();
    final code = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    final start = code.indexOf('animateToPage(page).whenComplete(');
    expect(start, isNot(-1), reason: '找不到动画完成回调（结构可能已改，请同步本守卫）');
    final end = code.indexOf('});', start);
    final block = code.substring(start, end);

    final guard = block.indexOf(
      'if (_disposed || token != _animToken) return;',
    );
    final sharedWrite = block.indexOf('_pageAnimatingFallback?.cancel()');
    expect(guard, isNot(-1), reason: '缺少代次/存活校验 ✗');
    expect(sharedWrite, isNot(-1), reason: '找不到共享兜底 Timer 的取消点（结构可能已改）');
    expect(
      guard < sharedWrite,
      isTrue,
      reason:
          '代次校验必须**提到最前** ✗→✓ —— 否则被顶掉的旧动画（其 future 会立即完成 ✓）迟到时会先掐掉'
          '**新一代**的兜底 Timer ✓ ⇒ 本代动画失去兜底 ⇒ `_pageAnimating` 永久为 true ⇒'
          '`AbsorbPointer` 永久吸收内容区手势（用户最初报的 bug 复发路径 ✗）',
    );
  });
}
