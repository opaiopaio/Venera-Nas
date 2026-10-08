import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// 二级页面**统一表面** `SecondaryPageSurface` 的语义回归（见 doc-private 12 号文档）。
///
/// 锁死两条使用路径的差异，防止将来"顺手统一"把语义改坏：
/// - `ContentDialog`（默认）：**补主题表面色 + 裁剪圆角**（否则弹窗会透出下层内容 ✗）
/// - `PopUpWidgetScaffold`（`fallbackToSurface: false, clip: false`）：
///   形状/底色由**自身路由的 decoration** 负责（`PopUpWidget.buildPage`），表面不得再补 ✗
void main() {
  Future<void> pumpSurface(WidgetTester tester, Widget surface) async {
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: surface)),
      ),
    );
  }

  /// 置为「二级页面体系关闭」→ `secondaryPageDecoration()`/`customSecondarySurfaceColor()`
  /// 均返回 null，从而让"是否补主题表面色"这一点可确定性断言。
  /// ⭐ P2：同时把**新增**的「跟随系统主题」总开关置 false ✓ —— 它默认 true，会**强制补主题表面色** ✓
  ///（这正是 P2 要的"遮挡" ✓），否则这些"体系关闭"断言会被它覆盖 ✗。
  void disableSecondaryPageFeature() {
    final old = appdata.settings['secondaryPageMode'];
    final oldFollow = appdata.settings['secondaryPageFollowTheme'];
    addTearDown(() {
      appdata.settings['secondaryPageMode'] = old;
      appdata.settings['secondaryPageFollowTheme'] = oldFollow;
    });
    appdata.settings['secondaryPageMode'] = 'off';
    appdata.settings['secondaryPageFollowTheme'] = false;
  }

  /// ⭐ P2（用户反馈 ✓）：**跟随系统主题（默认）**时，弹层必须补一层**主题表面色** ✓
  /// = "遮挡下面内容" ✓；否则弹层透明 ✗ → 背后的暗罩直接透出来（观感"透明 + 变深" ✗）
  /// 且暗罩盖满全屏（观感"没有周围变暗突出" ✗）。
  testWidgets('跟随系统主题：仍补主题表面色（保证遮挡，暗罩只在弹层之外起作用）', (tester) async {
    final oldMode = appdata.settings['secondaryPageMode'];
    final oldFollow = appdata.settings['secondaryPageFollowTheme'];
    addTearDown(() {
      appdata.settings['secondaryPageMode'] = oldMode;
      appdata.settings['secondaryPageFollowTheme'] = oldFollow;
    });
    appdata.settings['secondaryPageFollowTheme'] = true;
    // 即便显式 `fallbackToSurface: false`（PopUpWidgetScaffold 的姿势），跟随时也要补 ✓
    await pumpSurface(
      tester,
      const SecondaryPageSurface(
        fallbackToSurface: false,
        clip: false,
        child: SizedBox(width: 80, height: 40),
      ),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsWidgets,
      reason: '跟随系统主题时必须补主题表面色（遮挡下面内容）',
    );
  });

  testWidgets('默认（ContentDialog 路径）：补主题表面色 + 裁剪圆角', (tester) async {
    disableSecondaryPageFeature();
    await pumpSurface(
      tester,
      const SecondaryPageSurface(child: SizedBox(width: 80, height: 40)),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(surface, findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byType(ClipRRect)),
      findsOneWidget,
      reason: '默认应裁剪圆角（ContentDialog 需要）',
    );
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsWidgets,
      reason: '体系关闭时应补主题表面色，避免弹窗透出下层内容',
    );
  });

  testWidgets('PopUpWidgetScaffold 路径：不裁剪、不补底（形状与底色由路由 decoration 负责）', (
    tester,
  ) async {
    disableSecondaryPageFeature();
    await pumpSurface(
      tester,
      const SecondaryPageSurface(
        clip: false,
        fallbackToSurface: false,
        child: SizedBox(width: 80, height: 40),
      ),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(
      find.descendant(of: surface, matching: find.byType(ClipRRect)),
      findsNothing,
      reason: 'PopUpWidgetScaffold 的圆角由路由 decoration/Clip.antiAlias 提供',
    );
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsNothing,
      reason: 'PopUpWidgetScaffold 不得自行补底色（会盖住路由 decoration 的观感）',
    );
  });
}
