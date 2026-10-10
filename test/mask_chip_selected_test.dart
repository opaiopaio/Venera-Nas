import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';

/// ⭐ 选中态可辨性守护（2026-10-10 用户反馈 ✓）。
///
/// 用户实测 ✗：「在所有外观自定义设置都跟随主题颜色的情况下，搜索页面的漫画源、排序、分类等按钮，
/// **选中效果只有黑色描边差距（被选中的没有黑色描边）**，太不明显了，根本看不出按钮被选中」✓。
///
/// 旧实现根因 ✓：选中填充 `secondaryContainer` ＋ **描边与填充同色** ✗，
/// 而未选中填充是 `tagOverlayColor()`（系统容器色 × 0.85 ✓）⇒ 两者在"跟随主题"时几乎同色 ✓
/// ⇒ 唯一差别只剩"未选中才有描边" ✓。
///
/// 现契约 ✓（`components/mask_chip.dart` ✓）：**选中 = 颜色变化** ——
/// 填充 `primaryContainer` ✓、文字 `onPrimaryContainer` ✓、描边 `primary` ✓；
/// 未选中 = `tagOverlayColor()` ＋ `outline` ＋ 主题文字色 ✓。
/// 本守护在**亮色**与**深色**两套主题下都断言：① 两者填充不同 ✓；② 选中文字用 `onPrimaryContainer` ✓
///（成对色 ⇒ 对比度有保证 ✓，不出现"深底深字" ✗）。
void main() {
  Future<void> pumpChips(
    WidgetTester tester,
    ThemeData theme,
    ColorScheme scheme,
  ) async {
    await tester.pumpWidget(
      // ⚠️ `MaskChip` 依赖 `AppSettingsScope` ✓（用 `AppSettingsScope.of` 建设置依赖 ✓）
      // ⇒ 测试必须按 `main.dart` 的方式包一层 ✓（与既有 widget 测试同做法 ✓）。
      AppSettingsScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                MaskChip(text: 'SEL', selected: true, onTap: () {}),
                MaskChip(text: 'UNSEL', selected: false, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color? fillOf(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration as BoxDecoration?;
    return decoration?.color;
  }

  Color? borderOf(WidgetTester tester, String label) {
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration as BoxDecoration?;
    return decoration?.border?.top.color;
  }

  void expectDistinct(WidgetTester tester, ColorScheme scheme, String mode) {
    final selFill = fillOf(tester, 'SEL');
    final unselFill = fillOf(tester, 'UNSEL');
    expect(
      selFill,
      isNot(unselFill),
      reason: '[$mode] 选中与未选中的填充色必须不同 ⇒ 否则用户看不出谁被选中（原 bug ✓）',
    );
    expect(
      selFill,
      scheme.primaryContainer,
      reason: '[$mode] 选中填充必须走 `primaryContainer` ✓（更强的色调 ✓）',
    );
    expect(
      borderOf(tester, 'SEL'),
      scheme.primary,
      reason: '[$mode] 选中描边必须是 `primary` ✓（不能与填充同色 ✗）',
    );
    final selText = tester.widget<Text>(find.text('SEL')).style?.color;
    expect(
      selText,
      scheme.onPrimaryContainer,
      reason: '[$mode] 选中文字必须用成对色 `onPrimaryContainer` ✓ ⇒ 保证对比度（不许"深底深字"✗）',
    );
    expect(
      tester.widget<Text>(find.text('UNSEL')).style?.color,
      isNull,
      reason: '[$mode] 未选中文字沿用主题色 ✓（不显式指定 ✓）',
    );
  }

  testWidgets('T-CHIP1 亮色主题下选中一眼可辨', (tester) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2143F3)),
    );
    await pumpChips(tester, theme, theme.colorScheme);
    expectDistinct(tester, theme.colorScheme, 'light');
  });

  testWidgets('T-CHIP2 深色主题下选中一眼可辨', (tester) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2143F3),
        brightness: Brightness.dark,
      ),
    );
    await pumpChips(tester, theme, theme.colorScheme);
    await tester.pump();
    expectDistinct(tester, theme.colorScheme, 'dark');
  });

  testWidgets('T-CHIP3 自定义配色（非默认种子）下仍成立', (tester) async {
    // 模拟"外观全部自定义"：换个种子色 ✓ ⇒ 成对色依旧成立 ✓（这正是用户抱怨的场景 ✓）。
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB3261E)),
    );
    await pumpChips(tester, theme, theme.colorScheme);
    expectDistinct(tester, theme.colorScheme, 'custom-seed');
  });
}
