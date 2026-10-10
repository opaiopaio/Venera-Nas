import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/favorites.dart';
import 'package:venera_nas/pages/favorites/favorites_page.dart';
import 'package:venera_nas/utils/translations.dart';

/// ⭐ 本轮（用户实测反馈 ✓）回归守护：收藏侧栏文件夹行的**墨迹（hover 预览 + 点击涟漪）
/// 必须与「圆角高亮矩形」重合**，不得外溢 ✓。
///
/// 用户澄清 ✓：「**高亮圆角矩形才是我们设置的遮罩** ✓（预期设计，不要改窄/去色/改圆角 ✗）——
/// 那个**半透明遮罩其实是鼠标放上去的预览** ✓，点击还有**涟漪效果**」✓，两者都溢出了遮罩 ✗。
///
/// 真因 ✓：`_buildFolderRow` 原先把 `Container.margin` 放在 `InkWell` **里面** ✗ ——
/// Flutter 的 hover 高亮与涟漪都按 `InkWell` **自身矩形**（+ `borderRadius` ✓）绘制
///（SDK 证据：`ink_highlight.dart` 用 `Offset.zero & referenceBox.size` ✓；
///  `ink_splash.dart` 的 `_getClipCallback` 在 `containedInkWell` 时返回 referenceBox 矩形 ✓；
///  `InkWell` 恒为 `containedInkWell: true` ✓，见 `ink_well.dart` ✓）⇒
/// 墨迹矩形比遮罩矩形**左右各宽一个 margin、上下各高一个 margin** ✗。
/// 修法 ✓：`margin` 移到 `InkWell` 外面的 `Padding` ✓ + `InkWell` 传与遮罩**同源**的
/// `windowOverlayBorderRadius()` ✓（**不缩小整行** ✓：行占位/内容位置不变 ✓，只让墨迹与遮罩同矩形 ✓）。
///
/// 实测（真实侧栏，1200×800 双栏 ✓）：
/// - 修复前：`InkWell` = 255.4×46.0，遮罩 = 239.4×42.0 ⇒ 左右各溢出 8、上下各溢出 2 ✗；
/// - 修复后：`InkWell` = 239.4×42.0 = 遮罩 ✓。
void main() {
  testWidgets('T-SBR1 侧栏文件夹行：hover/涟漪矩形与圆角遮罩完全重合', (tester) async {
    // `_LeftBar` 要读 `LocalFavoritesManager().folderNames` ⇒ 必须先建库 ✓；
    // ⚠️ 真实异步初始化必须放 `runAsync` ✗→✓（否则 fake async 下会挂死 ✓ 已实测）。
    try {
      AppTranslation.translations = <String, Map<String, String>>{};
    } catch (_) {}
    final tempDir = Directory.systemTemp.createTempSync(
      'venera-sidebar-guard-',
    );
    addTearDown(() {
      // sqlite 仍持句柄 ⇒ 删除可能失败 ✓（与断言无关 ✓）。
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    App.dataPath = tempDir.path;
    await tester.runAsync(() async {
      await appdata.init();
      await LocalFavoritesManager().init();
    });

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: FavoritesPage())),
      ),
    );
    // ⚠️ 不能用 `pumpAndSettle`：树里有常驻动画 ⇒ 会等到超时 ✗（已实测）。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 「All」（= `_localAllFolderLabel` 的 `"All".tl` ✓）是本地区的第一行 ✓。
    final rowText = find.text('All');
    expect(
      rowText.evaluate(),
      isNotEmpty,
      reason: '侧栏没有渲染出文件夹行 ⇒ 本测试无法验证（请检查 DB 初始化 ✓）',
    );

    final inkFinder = find.ancestor(
      of: rowText,
      matching: find.byType(InkWell),
    );
    expect(inkFinder.evaluate(), isNotEmpty, reason: '文件夹行应由 InkWell 承载');
    final inkSize = tester.getSize(inkFinder.first);

    final maskFinder = find.descendant(
      of: inkFinder,
      matching: find.byType(DecoratedBox),
    );
    expect(maskFinder.evaluate(), isNotEmpty, reason: '文件夹行应有圆角遮罩 decoration');
    final maskSize = tester.getSize(maskFinder.first);

    final listViewWidth = tester.getSize(find.byType(ListView).first).width;
    expect(
      maskSize.width,
      lessThan(listViewWidth),
      reason: '遮罩应比侧栏窄（左右各有 margin ✓）⇒ 否则本断言失去意义',
    );

    // ① 墨迹矩形必须**完全等于**遮罩矩形 ✓（溢出即失败 ✓）。
    expect(
      inkSize,
      maskSize,
      reason: 'hover 预览/涟漪的矩形（InkWell）与圆角遮罩矩形不一致 ⇒ 会溢出遮罩（用户实测 ✗）',
    );
    // ② 圆角必须**同源** ✓（一个为 null / 用别的档位 ⇒ 溢出的圆角对不上 ✓）。
    final inkRadius = tester.widget<InkWell>(inkFinder.first).borderRadius;
    final decoration = tester.widget<DecoratedBox>(maskFinder.first).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect(
      inkRadius,
      (decoration as BoxDecoration).borderRadius,
      reason: 'InkWell 的 borderRadius 必须与遮罩 decoration 的圆角一致（同源 ✓）',
    );
  });

  test('T-SBR2 同类第三份实现（_FolderTile）保持裁剪，防回退', () {
    // 该实现用 `Material(clipBehavior: Clip.antiAlias, borderRadius: …)` 自行裁剪 ✓，
    // 当前**没有**同类溢出 ⇒ 本轮未改 ✓，仅在此锁住防回退 ✓。
    final f = File('lib/pages/favorites/network_favorites_page.dart');
    expect(f.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');
    final src = _stripComments(f.readAsStringSync());
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

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// 去掉 `//` 行注释与 `/* */` 块注释（避免把注释里的字样当成代码 ✗）。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
