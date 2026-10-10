import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

/// 自绘填充上的前景色守护（`FilledForeground` / `onColorForFill`）。
///
/// 契约（全项目统一）：
/// ① 用户设了「全局文字颜色」 ⇒ 填充上的文字/图标**必须跟随用户设置**；
/// ② 未设置（`globalTextColor()` 为 null） ⇒ 按填充亮度在**黑/白**之间择一；
/// ③ 无填充 / 全透明 ⇒ **原样返回**，不做任何注入。
///
/// 本文件**自足**：只改 `appdata.settings` 与主题，不触碰 `ImageCache` 或原生缓存。
void main() {
  const textKey = 'globalTextColor';
  const followKey = 'textFollowTheme';
  late dynamic originalText;
  late dynamic originalFollow;

  setUp(() {
    originalText = appdata.settings[textKey];
    originalFollow = appdata.settings[followKey];
    // 「跟随系统」总开关开启时 `globalTextColor()` 恒为 null ⇒ 先明确关掉。
    appdata.settings[followKey] = false;
  });

  tearDown(() {
    appdata.settings[textKey] = originalText;
    appdata.settings[followKey] = originalFollow;
  });

  /// 让 `FilledForeground` 生效并取回它给子树注入的前景色。
  Future<Color?> pumpFill(WidgetTester tester, Color? fill) async {
    Color? effective;
    await tester.pumpWidget(
      // `FilledForeground` 依赖 `AppSettingsScope` ✓（用 `AppSettingsScope.of` 建设置依赖 ✓）。
      AppSettingsScope(
        child: MaterialApp(
          home: Scaffold(
            body: FilledForeground(
              fill: fill,
              child: Builder(
                builder: (context) {
                  effective = DefaultTextStyle.of(context).style.color;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return effective;
  }

  testWidgets('T-FF1 用户设了全局文字色 ⇒ 填充上的文字跟随该色', (tester) async {
    appdata.settings[textKey] = '#123456';
    expect(globalTextColor(), const Color(0xFF123456));
    // 深填充（本会配白字）也必须让位给用户设置 ✓ —— 这正是此前丢失的一层。
    final on = await pumpFill(tester, const Color(0xFF101010));
    expect(on, const Color(0xFF123456), reason: '用户设置优先于自动对比色');
  });

  testWidgets('T-FF2 未设置 ⇒ 按填充亮度取黑/白', (tester) async {
    appdata.settings[textKey] = 'system';
    expect(globalTextColor(), isNull);
    expect(
      await pumpFill(tester, const Color(0xFF101010)),
      Colors.white,
      reason: '暗填充配浅字',
    );
    expect(
      await pumpFill(tester, const Color(0xFFFDFDFD)),
      Colors.black,
      reason: '亮填充配深字',
    );
  });

  testWidgets('T-FF3 半透明填充先与主题表面合成', (tester) async {
    appdata.settings[textKey] = 'system';
    final surface = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2143F3)),
    ).colorScheme.surface;
    final blended = Color.alphaBlend(const Color(0x1A000000), surface);
    final expected =
        ThemeData.estimateBrightnessForColor(blended) == Brightness.dark
        ? Colors.white
        : Colors.black;
    expect(
      await pumpFill(tester, const Color(0x1A000000)),
      expected,
      reason: '忽略 alpha 会误判亮度 ⇒ 必须先合成',
    );
  });

  testWidgets('T-FF4 无填充/全透明 ⇒ 不注入任何前景色', (tester) async {
    appdata.settings[textKey] = '#123456';
    final transparent = await pumpFill(tester, const Color(0x00000000));
    expect(transparent, isNot(const Color(0xFF123456)));
    final none = await pumpFill(tester, null);
    expect(none, isNot(const Color(0xFF123456)));
  });

  testWidgets('T-FF5 「跟随系统」总开关开启 ⇒ 不注入（回到主题默认）', (tester) async {
    appdata.settings[textKey] = '#123456';
    appdata.settings[followKey] = true;
    expect(globalTextColor(), isNull);
    final on = await pumpFill(tester, const Color(0xFF101010));
    expect(on, Colors.white, reason: '总开关开启时回到按填充亮度的自动配色');
  });
}
