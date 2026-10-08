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

  testWidgets('整页式路径：不裁剪；无背景图（decoration 为 null）时必须补底保证遮挡', (tester) async {
    disableSecondaryPageFeature();
    await pumpSurface(
      tester,
      const SecondaryPageSurface(
        clip: false,
        fallbackToSurface: false,
        // ⭐ R1：整页式（`PopUpWidgetScaffold`）传 `popupStyle: false` ✓ ——
        // 弹出式（默认 true ✓）现在**无条件补不透明底** ✓（R1 修复：色盘等对话框在
        // "自定义开启"时也必须遮挡 ✓），故本用例必须显式声明自己不是弹出式 ✓。
        popupStyle: false,
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
      findsWidgets,
      reason:
          '⭐ R1：无背景图（decoration == null）时必须补**不透明底** ✓ —— '
          '否则"自定义开启 + 无背景图"时整页式弹层（如色盘）会透明透出下层内容 ✗（用户截图实测 ✓）',
    );
  });

  /// ⭐ R1（用户反馈 ✓）：**弹出式**对话框在"**自定义开启**"（非跟随主题）时，
  /// 也必须补一层**不透明主题表面色** ✓ —— 否则只叠了半透明色调 → **遮挡失效** ✗
  ///（用户实测："打开自定义后色盘这部分全部失效" ✓）。
  testWidgets('弹出式 + 自定义开启：仍补不透明表面色（保证遮挡）', (tester) async {
    final oldMode = appdata.settings['secondaryPageMode'];
    final oldFollow = appdata.settings['secondaryPageFollowTheme'];
    addTearDown(() {
      appdata.settings['secondaryPageMode'] = oldMode;
      appdata.settings['secondaryPageFollowTheme'] = oldFollow;
    });
    appdata.settings['secondaryPageFollowTheme'] = false; // 自定义开启 ✓
    appdata.settings['secondaryPageMode'] = 'opaque'; // 体系启用 → tint 非空 ✓
    await pumpSurface(
      tester,
      const SecondaryPageSurface(child: SizedBox(width: 80, height: 40)),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsWidgets,
      reason: '弹出式必须始终有不透明底（否则遮挡失效）',
    );
  });
}
