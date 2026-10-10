import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

/// 自绘填充上的前景色守护（`FilledForeground` / `onColorForFill` / `fillForeground`）。
///
/// 契约（全项目统一）：
/// ① 用户设了「全局文字颜色」 ⇒ 填充上的**文字**跟随用户设置，**图标**跟随「图标颜色」；
/// ② 未设置 ⇒ 文字按填充亮度取**绝对黑/白**；图标 = `appIconColor(context, 对比色)`；
/// ③ 无填充 / 全透明 ⇒ **原样返回**（文字与图标都不得被注入）；
/// ④ `userColorWins: false`（主题成对色/选中态）⇒ 用户文字色**不得**覆盖对比色；
/// ⑤ 改设置后**不重建整棵树**也要即时刷新（`AppSettingsScope` 依赖）。
///
/// 本文件**自足**：只改 `appdata.settings` 与主题，不触碰 `ImageCache` 或原生缓存。
void main() {
  const textKey = 'globalTextColor';
  const followKey = 'textFollowTheme';
  const iconKey = 'globalIconColor';
  const seed = Color(0xFF2143F3);
  late Map<String, dynamic> original;

  setUp(() {
    original = {
      for (final k in [textKey, followKey, iconKey]) k: appdata.settings[k],
    };
    appdata.settings[followKey] = false;
    appdata.settings[iconKey] = 'system';
  });

  tearDown(() {
    original.forEach((k, v) => appdata.settings[k] = v);
  });

  /// ⚠️ 子树自带**哨兵色** ⇒ 无填充时必须原样保留 ✓（否则删掉短路也抓不到 ✗）。
  const sentinel = Color(0xFF00FF00);

  /// 量 `FilledForeground` 注入的**文字色与图标色**（各自独立读数 ✓）。
  Future<({Color? text, Color? icon})> pumpFill(
    WidgetTester tester,
    Color? fill, {
    bool userColorWins = true,
  }) async {
    Color? text;
    Color? icon;
    // 同一个 `ThemeData` 用于合成与期望 ✓（早先用另一个主题的 surface ⇒ 边界样本会误判 ✗）。
    final theme = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed));
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            // ⚠️ 哨兵色必须放在**包装之外**（祖先）✓ —— 放在里面会盖住注入 ⇒ 测不到注入 ✗；
            // 放在外面时：无填充 ⇒ 原样透传哨兵色 ✓；有填充 ⇒ `merge` 覆盖哨兵色 ✓。
            body: DefaultTextStyle(
              style: const TextStyle(color: sentinel),
              child: IconTheme(
                data: const IconThemeData(color: sentinel),
                child: FilledForeground(
                  fill: fill,
                  userColorWins: userColorWins,
                  child: Builder(
                    builder: (context) {
                      text = DefaultTextStyle.of(context).style.color;
                      icon = IconTheme.of(context).color;
                      return const SizedBox(key: probeKey);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (text: text, icon: icon);
  }

  Color contrastOf(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
      ? Colors.white
      : Colors.black;

  testWidgets('T-FF1 用户设了全局文字色 ⇒ 填充上的文字跟随该色', (tester) async {
    appdata.settings[textKey] = '#123456';
    expect(globalTextColor(), const Color(0xFF123456));
    final r = await pumpFill(tester, const Color(0xFF101010));
    expect(r.text, const Color(0xFF123456), reason: '用户设置优先于自动对比色');
  });

  testWidgets('T-FF2 未设置 ⇒ 文字按填充亮度取黑/白，图标走图标色入口', (tester) async {
    appdata.settings[textKey] = 'system';
    expect(globalTextColor(), isNull);
    final dark = await pumpFill(tester, const Color(0xFF101010));
    expect(dark.text, Colors.white, reason: '暗填充配浅字');
    expect(dark.icon, Colors.white, reason: '未设图标色 ⇒ 图标按对比色（与文字同源）');
    final light = await pumpFill(tester, const Color(0xFFFDFDFD));
    expect(light.text, Colors.black, reason: '亮填充配深字');
    expect(light.icon, Colors.black);
  });

  testWidgets('T-FF2b 设了「图标颜色」⇒ 图标跟随它、且与文字色解耦', (tester) async {
    appdata.settings[textKey] = '#123456';
    appdata.settings[iconKey] = '#FF00FF';
    final r = await pumpFill(tester, const Color(0xFF101010));
    expect(r.text, const Color(0xFF123456), reason: '文字跟随文字色');
    expect(r.icon, const Color(0xFFFF00FF), reason: '图标只跟随图标色（不跟文字色 ✗）');
  });

  testWidgets('T-FF3 半透明填充先与主题表面合成（同一主题 ⇒ 期望同源）', (tester) async {
    appdata.settings[textKey] = 'system';
    final surface = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
    ).colorScheme.surface;
    const semi = Color(0x1A000000);
    final blended = Color.alphaBlend(semi, surface);
    expect(
      (await pumpFill(tester, semi)).text,
      contrastOf(blended),
      reason: '忽略 alpha 会误判亮度 ⇒ 必须先合成',
    );
    // 边界样本：合成后恰在亮/暗分界附近（`estimateBrightnessForColor` 阈值 0.15 ✓）
    for (final f in const [
      Color(0x14000000),
      Color(0x26FFFFFF),
      Color(0x33000000),
      Color(0x0DFFFFFF),
    ]) {
      final expectOn = contrastOf(Color.alphaBlend(f, surface));
      expect(
        (await pumpFill(tester, f)).text,
        expectOn,
        reason: '边界样本 $f 必须与"合成后再判亮度"一致',
      );
    }
  });

  testWidgets('T-FF4 无填充/全透明 ⇒ 原样返回（哨兵色必须被保留）', (tester) async {
    appdata.settings[textKey] = '#123456';
    appdata.settings[iconKey] = '#FF00FF';
    for (final fill in const [null, Color(0x00000000)]) {
      final r = await pumpFill(tester, fill);
      expect(r.text, sentinel, reason: '无填充 ⇒ 文字保持子树自己的哨兵色');
      expect(r.icon, sentinel, reason: '无填充 ⇒ 图标保持子树自己的哨兵色');
    }
  });

  testWidgets('T-FF5 用户文字色不得覆盖成对色：`userColorWins: false`', (tester) async {
    appdata.settings[textKey] = '#123456';
    // 亮填充 ⇒ 对比色为黑；传 false 时必须仍是黑（用户色不生效）
    final r = await pumpFill(
      tester,
      const Color(0xFFFDFDFD),
      userColorWins: false,
    );
    expect(r.text, Colors.black, reason: '成对色/选中态：用户文字色不得覆盖对比色');
    expect(r.icon, Colors.black);
  });

  testWidgets('T-FF6 改设置后不重建整棵树也即时刷新（AppSettingsScope 依赖）', (tester) async {
    appdata.settings[textKey] = 'system';
    await pumpFill(tester, const Color(0xFF101010));
    expect(probeText(tester), Colors.white);
    appdata.settings[textKey] = '#123456';
    // ⚠️ 不重新 pumpWidget ⇒ 只靠设置通知触发重建 ✓
    await tester.pump();
    expect(
      probeText(tester),
      const Color(0xFF123456),
      reason: '前景必须随设置即时刷新（`AppSettingsScope.of` 依赖）',
    );
  });
}

/// 探针 key：从当前树里读**刷新后**的文字色 ✓（用于"改设置即刷新"用例 ✓）。
const probeKey = Key('ff-probe');

Color? probeText(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(find.byKey(probeKey))).style.color;
