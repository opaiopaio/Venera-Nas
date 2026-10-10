import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

/// 守护：**「全局文字样式」注入必须对字体度量保持中性**。
///
/// 契约 ✓：用户**只**设置了「文字颜色」时，主题各文字样式的
/// `fontSize` / `height` / `letterSpacing` 与**继承型文字**（`ListTile` 选项行标题、
/// 未写字号的环境文字 ✓）的渲染尺寸，必须与**未设置时逐项一致** ✓；
/// 只有用户**显式**改过「字体」「字号缩放」时才允许改变度量 ✓。
///
/// ⚠️ 两条铁律（都踩过）✗：
/// ① 必须调**生产函数** `applyGlobalTextStyleToTheme` ✓ —— 早先在测试里"复刻"注入链 ✗，
///    结果 `main.dart` 回退成旧的 `listTileTheme.titleTextStyle` 写法时用例**照样全绿** ✗（假绿 ✓）；
/// ② 必须用**没有显式字号的继承型文字** ✗ —— 显式 `fontSize` 的样本本就不吃注入样式 ✓。
void main() {
  const textKey = 'globalTextColor';
  const followKey = 'textFollowTheme';
  const familyKey = 'globalFontFamily';
  const fileKey = 'globalFontFile';
  const scaleKey = 'globalFontScale';
  late Map<String, dynamic> original;

  setUp(() {
    original = {
      for (final k in [textKey, followKey, familyKey, fileKey, scaleKey])
        k: appdata.settings[k],
    };
    // 总开关默认 true（该页自定义项一律不生效）⇒ 逐个断言前先关掉它。
    appdata.settings[followKey] = false;
    appdata.settings[familyKey] = 'system';
    appdata.settings[fileKey] = '';
    appdata.settings[scaleKey] = 1.0;
  });

  tearDown(() {
    original.forEach((k, v) => appdata.settings[k] = v);
  });

  /// 用**生产注入函数**建主题，并渲染继承型文字 + `ListTile` 选项行。
  Future<Map<String, Object?>> pipeline(WidgetTester tester) async {
    final theme = applyGlobalTextStyleToTheme(
      ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2143F3)),
        fontFamily: 'Noto Sans CJK',
        fontFamilyFallback: const ['Segoe UI', 'Noto Sans SC', 'Noto Sans'],
      ),
    );
    TextTheme? resolved;
    // ⚠️ 先拆空树：直接换主题会让 `ListTile` 内的 `AnimatedDefaultTextStyle` 在新旧样式间
    // 做隐式 lerp（两者 `inherit` 不同 ⇒ lerp 断言失败 ✗）⇒ 两态必须各自**独立建树** ✓。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          theme: theme,
          builder: (context, child) {
            final gStyle = globalTextStyle();
            if (gStyle != null) {
              return DefaultTextStyle.merge(style: gStyle, child: child!);
            }
            return child!;
          },
          home: Builder(
            builder: (context) {
              resolved = Theme.of(context).textTheme;
              return const Scaffold(
                body: Column(
                  children: [
                    ListTile(title: Text('选项标签', key: Key('row'))),
                    Text('裸继承文字', key: Key('bare')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final out = <String, Object?>{};
    for (final e in {
      'bodyLarge': resolved!.bodyLarge,
      'bodyMedium': resolved!.bodyMedium,
      'titleSmall': resolved!.titleSmall,
      'labelSmall': resolved!.labelSmall,
    }.entries) {
      out['${e.key}.size'] = e.value?.fontSize;
      out['${e.key}.height'] = e.value?.height;
      out['${e.key}.spacing'] = e.value?.letterSpacing;
      out['${e.key}.family'] = e.value?.fontFamily;
    }
    // 选项行标题真正生效的样式（`ListTile` 内部的 `AnimatedDefaultTextStyle` ✓）
    out['rowStyle'] = tester
        .widgetList<AnimatedDefaultTextStyle>(
          find.byType(AnimatedDefaultTextStyle),
        )
        .map(
          (e) =>
              'size=${e.style.fontSize},h=${e.style.height},ls=${e.style.letterSpacing}',
        )
        .join(' | ');
    out['rowSize'] = tester.getSize(find.byKey(const Key('row')));
    out['bareSize'] = tester.getSize(find.byKey(const Key('bare')));
    return out;
  }

  testWidgets('T-GTS1 只设文字颜色 ⇒ 继承型文字与选项行的度量/尺寸逐项不变', (tester) async {
    appdata.settings[textKey] = 'system';
    final on = await pipeline(tester);
    // 未设颜色时主题字号与选项行字号必须存在（否则守护本身失效 ✗）
    expect(on['bodyLarge.size'], isNotNull);
    expect(on['rowStyle'], contains('size=16.0'));

    appdata.settings[textKey] = '#7B1FA2';
    final off = await pipeline(tester);
    expect(off, on, reason: '只改文字颜色不允许改动任何字体度量或渲染尺寸');
    expect(off['rowStyle'], contains('size=16.0'), reason: '选项行字号必须保持 16 ✓');
  });

  testWidgets('T-GTS2 显式选字体 ⇒ 主题字体族随之改变，且字号不变', (tester) async {
    appdata.settings[textKey] = '#123456';
    final none = await pipeline(tester);
    appdata.settings[familyKey] = 'SimHei';
    expect(globalFontFamily(), 'SimHei');
    final fonted = await pipeline(tester);
    expect(fonted['bodyMedium.family'], 'SimHei', reason: '显式选字体时必须真的换字体族');
    expect(
      fonted['bodyMedium.size'],
      none['bodyMedium.size'],
      reason: '换字体不得改变字号',
    );
  });

  testWidgets('T-GTS3 字号缩放：1 / 1(int) 不缩放，0.8 生效', (tester) async {
    appdata.settings[textKey] = '#123456';
    appdata.settings[scaleKey] = 1;
    expect(globalFontScale(), 1.0);
    appdata.settings[scaleKey] = 0.8;
    expect(globalFontScale(), 0.8);
  });

  testWidgets('T-GTS4 空字符串字体 + 缩放 1 + 只切总开关 ⇒ 逐项不变', (tester) async {
    appdata.settings[familyKey] = '';
    appdata.settings[fileKey] = '';
    appdata.settings[scaleKey] = 1;
    appdata.settings[textKey] = '#123456';

    appdata.settings[followKey] = true;
    final on = await pipeline(tester);

    appdata.settings[followKey] = false;
    expect(globalFontFamily(), isNull, reason: '空字符串必须等价于"未设置"');
    final off = await pipeline(tester);
    expect(off, on, reason: '只切总开关不允许改动任何字体度量或渲染尺寸');
  });

  group('T-GTS5 静态接线（防"假绿"：注入必须走可测的生产函数）', () {
    String strip(String src) => src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('main.dart 调生产函数，且不得再自行注入 ListTile 文字样式', () {
      final main = strip(File('lib/main.dart').readAsStringSync());
      expect(
        main.contains('applyGlobalTextStyleToTheme'),
        isTrue,
        reason: '主题注入必须走 foundation 的可测函数（否则单测覆盖不到）',
      );
      expect(
        main.contains('titleTextStyle'),
        isFalse,
        reason: '从 theme.textTheme 派生的 TextStyle 不含度量 ⇒ 会顶掉选项行默认字号',
      );
      expect(main.contains('subtitleTextStyle'), isFalse, reason: '同上');
    });

    test('生产函数只注入 listTileTheme.textColor', () {
      final src = strip(
        File('lib/foundation/text_style_settings.dart').readAsStringSync(),
      );
      final start = src.indexOf('ThemeData applyGlobalTextStyleToTheme');
      expect(start, isNonNegative, reason: '生产函数必须存在');
      final body = src.substring(start, (start + 1200).clamp(0, src.length));
      expect(body.contains('listTileTheme'), isTrue);
      expect(body.contains('textColor'), isTrue);
      expect(body.contains('titleTextStyle'), isFalse);
      expect(body.contains('subtitleTextStyle'), isFalse);
    });
  });
}
