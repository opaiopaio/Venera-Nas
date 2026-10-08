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

  /// ⭐ U1：读出弹层**底**（`Stack` 中最底层那个 `ColoredBox` ✓）的颜色。
  Color baseColorOf(WidgetTester tester) {
    final boxes = tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(SecondaryPageSurface),
            matching: find.byType(ColoredBox),
          ),
        )
        .toList();
    expect(boxes, isNotEmpty, reason: '弹层必须有底（T1 不变量 ✓）');
    return boxes.first.color;
  }

  /// ⭐ U1（用户反馈 ✓）：`secondaryPageMode` 决定底的**透明度** ✓、
  /// `secondaryPageTint` 决定底的**深浅** ✓（必须是"更深/更浅的**面板**"✓，而不是蒙层灰 ✗）。
  testWidgets('U1：四种组合 —— 底随模式与色调变化', (tester) async {
    final oldMode = appdata.settings['secondaryPageMode'];
    final oldTint = appdata.settings['secondaryPageTint'];
    final oldStrength = appdata.settings['secondaryPageTintStrength'];
    final oldFollow = appdata.settings['secondaryPageFollowTheme'];
    addTearDown(() {
      appdata.settings['secondaryPageMode'] = oldMode;
      appdata.settings['secondaryPageTint'] = oldTint;
      appdata.settings['secondaryPageTintStrength'] = oldStrength;
      appdata.settings['secondaryPageFollowTheme'] = oldFollow;
    });
    appdata.settings['secondaryPageFollowTheme'] = false; // 自定义态 ✓
    Future<void> pump() => pumpSurface(
      tester,
      const SecondaryPageSurface(child: SizedBox(width: 80, height: 40)),
    );

    // ① opaque + tint=none → 底 = 纯主题表面色，**不透明** ✓
    appdata.settings['secondaryPageMode'] = 'opaque';
    appdata.settings['secondaryPageTint'] = 'none';
    await pump();
    final plain = baseColorOf(tester);
    expect(plain.a, 1.0, reason: '不透明模式：底必须完全不透明（保证遮挡 ✓）');

    // ② transparent → 底**带透明度** ✓（半透明档 ✓ → 能透出下层 ✓）
    appdata.settings['secondaryPageMode'] = 'transparent';
    await pump();
    final translucent = baseColorOf(tester);
    expect(
      translucent.a,
      lessThan(1.0),
      reason: '⭐ U1：半透明模式底必须带透明度（否则透不出下层 ✗，用户实测"变白底" ✗）',
    );

    // ③ darken → 比纯表面色**更深** ✓（且仍是实色面板 ✓，不是灰蒙层 ✗）
    appdata.settings['secondaryPageMode'] = 'opaque';
    appdata.settings['secondaryPageTint'] = 'darken';
    appdata.settings['secondaryPageTintStrength'] = 0.3;
    await pump();
    final darker = baseColorOf(tester);
    expect(
      darker.computeLuminance(),
      lessThan(plain.computeLuminance()),
      reason: '⭐ U1：darken 应得到"更深的面板"（用户实测"变灰色界面" ✗ 是蒙层做法 ✗）',
    );

    // ④ lighten → 比纯表面色**更浅** ✓
    appdata.settings['secondaryPageTint'] = 'lighten';
    await pump();
    final lighter = baseColorOf(tester);
    expect(
      lighter.computeLuminance(),
      greaterThan(plain.computeLuminance()),
      reason: '⭐ U1：lighten 应得到"更浅的面板"',
    );
  });

  /// ⭐ V1（用户反馈 ✓）：**整页式不受「弹出式二级页面」选项影响** ✓ ——
  /// 把弹出式的两个开关调到极端（半透明 + 强烈变深 ✓），整页式（`popupStyle: false` ✓）
  /// 的底必须**恒为不透明主题表面色** ✓（用户实测："弹出式选项会对整页式造成影响" ✗）。
  testWidgets('V1：整页式不受弹出式的模式/深浅影响（恒不透明）', (tester) async {
    final oldMode = appdata.settings['secondaryPageMode'];
    final oldTint = appdata.settings['secondaryPageTint'];
    final oldStrength = appdata.settings['secondaryPageTintStrength'];
    final oldFollow = appdata.settings['secondaryPageFollowTheme'];
    addTearDown(() {
      appdata.settings['secondaryPageMode'] = oldMode;
      appdata.settings['secondaryPageTint'] = oldTint;
      appdata.settings['secondaryPageTintStrength'] = oldStrength;
      appdata.settings['secondaryPageFollowTheme'] = oldFollow;
    });
    appdata.settings['secondaryPageFollowTheme'] = false;
    appdata.settings['secondaryPageMode'] = 'transparent'; // 极端：半透明 ✓
    appdata.settings['secondaryPageTint'] = 'darken'; // 极端：强烈变深 ✓
    appdata.settings['secondaryPageTintStrength'] = 0.6;
    await pumpSurface(
      tester,
      const SecondaryPageSurface(
        popupStyle: false, // 整页式 ✓
        fallbackToSurface: false,
        clip: false,
        child: SizedBox(width: 80, height: 40),
      ),
    );
    final base = baseColorOf(tester);
    expect(base.a, 1.0, reason: '⭐ V1：整页式不受弹出式的半透明模式影响（底恒不透明 ✓）');
  });
}
