import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⭐ 本轮（用户实测反馈 ✓）回归守护：收藏侧栏文件夹行的**墨迹矩形必须与圆角遮罩重合**。
///
/// 用户原话：文件夹按钮"点击之后涟漪效果和预览（鼠标放上去）阴影会**超出遮罩本身**" ✓。
/// 真因 ✓：`_buildFolderRow` 原先 `InkWell(... child: Container(margin: …))` ✗ ——
/// Flutter 的高亮/涟漪是按 `InkWell` **自身矩形**（+ `borderRadius` ✓）绘制的
///（SDK：`ink_highlight.dart` 的 `paintFeature` 用 `Offset.zero & referenceBox.size` ✓；
///  `ink_splash.dart` 的 `_getClipCallback` 在 `containedInkWell` 时返回 referenceBox 矩形 ✓），
/// 而 `Container.margin` 会**算进** `InkWell` 的矩形 ⇒ 墨迹比遮罩左右各宽一个 margin ✗。
/// 修法 ✓：`margin` 移到 `InkWell` 外面（`Padding` ✓）+ `InkWell` 传与遮罩**同源**的 `borderRadius` ✓。
///
/// 本文件用**静态守卫**锁住该结构 ✓（渲染真实侧栏需 DB/插件初始化 ⇒ 单测里会挂 ✗，
/// 项目既有同类守卫见 `test/ap1_static_regression_test.dart` ✓）。
void main() {
  String codeOf(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path 不存在（请在项目根目录运行 flutter test）');
    return _stripComments(f.readAsStringSync());
  }

  test('T-SBR1 侧栏文件夹行：margin 必须在 InkWell 外面且圆角同源', () {
    final src = codeOf('lib/pages/favorites/side_bar.dart');
    final start = src.indexOf('Widget _buildFolderRow(');
    expect(start, isNot(-1), reason: '找不到 _buildFolderRow（唯一实现 ✓）');
    final end = src.indexOf('Widget buildLocalFolder(String name)', start);
    expect(end, isNot(-1), reason: '_buildFolderRow 段未正常结束');
    final row = src.substring(start, end);

    expect(
      row.contains('margin:'),
      isFalse,
      reason: 'margin 又回到了 InkWell 内部 ⇒ 墨迹矩形会再次大于圆角遮罩（用户实测的溢出 ✗）',
    );
    expect(
      row.indexOf('Padding(') < row.indexOf('InkWell('),
      isTrue,
      reason: 'margin（Padding ✓）必须包在 InkWell **外面** ⇒ 墨迹矩形才与遮罩重合',
    );
    // 墨迹圆角与遮罩圆角必须**同源**（InkWell 一处 + decoration 一处 ⇒ 至少 2 处）。
    expect(
      RegExp(
        r'borderRadius:\s*windowOverlayBorderRadius\(\)',
      ).allMatches(row).length,
      greaterThanOrEqualTo(2),
      reason: 'InkWell 与遮罩的圆角必须取自同一个入口 windowOverlayBorderRadius()',
    );
  });

  test('T-SBR2 同类第三份实现（_FolderTile）保持裁剪，防回退', () {
    final src = codeOf('lib/pages/favorites/network_favorites_page.dart');
    final start = src.indexOf('class _FolderTile extends StatelessWidget');
    expect(start, isNot(-1), reason: '找不到 _FolderTile');
    final tail = src.substring(start);
    expect(
      tail.contains('clipBehavior: Clip.antiAlias'),
      isTrue,
      reason: '_FolderTile 靠 Material 的裁剪把墨迹收进圆角矩形 ⇒ 删掉会复发同类溢出',
    );
    expect(
      tail.contains('borderRadius: windowOverlayBorderRadius()'),
      isTrue,
      reason: '_FolderTile 的 Material 圆角必须与遮罩同源',
    );
  });
}

/// 去掉 `//` 行注释与 `/* */` 块注释（避免把注释里的字样当成代码 ✗）。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
