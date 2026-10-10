import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

/// 守护：**「全局文字样式」注入必须对字体度量保持中性**。
///
/// 约定：用户**只**设置了「文字颜色」时，主题里各文字样式的
/// `fontSize` / `height` / `letterSpacing` 与**继承型文字**（`ListTile` 选项行标题、
/// 未写字号的环境文字 ✓）的渲染尺寸，必须与**未设置时逐项一致** ✓；
/// 只有用户**显式**改过「字体」「字号缩放」时才允许改变度量。
///
/// ⚠️ 必须用**没有显式字号的继承型文字**测量 ✗ —— 显式写死 `fontSize` 的文字本来就不吃
/// 注入样式 ⇒ 永远测不出"只改颜色导致选项文字变小" ✗（踩过）。
void main() {
  const textKey = 'globalTextColor';
  const followKey = 'textFollowTheme';
  const familyKey = 'globalFontFamily';
  const scaleKey = 'globalFontScale';
  late Map<String, dynamic> original;

  setUp(() {
    original = {
      for (final k in [textKey, followKey, familyKey, scaleKey])
        k: appdata.settings[k],
    };
    // 总开关默认 true（该页自定义项一律不生效）⇒ 逐个断言前先关掉它。
    appdata.settings[followKey] = false;
    appdata.settings[familyKey] = 'system';
    appdata.settings[scaleKey] = 1.0;
  });

  tearDown(() {
    original.forEach((k, v) => appdata.settings[k] = v);
  });

  /// 复刻 `main.dart` 的注入链（`textTheme` + `listTileTheme` + `DefaultTextStyle.merge` ✓），
  /// 并渲染**继承型环境文字**与 **`ListTile` 选项行**（设置页选项行走的是 ListTile 默认标题样式 ✓）。
  Future<Map<String, Object?>> pipeline(WidgetTester tester) async {
    final gStyle = globalTextStyle();
    var theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2143F3)),
      fontFamily: 'Noto Sans CJK',
      fontFamilyFallback: const ['Segoe UI', 'Noto Sans SC', 'Noto Sans'],
    );
    if (gStyle != null) {
      theme = theme.copyWith(
        textTheme: decorateTextTheme(
          applyTextThemeOverrides(
            theme.textTheme,
            color: gStyle.color,
            fontFamily: gStyle.fontFamily,
          ),
        ),
        // 选项行只注入**颜色** ✓（`textColor` 由 `ListTile` 以 `copyWith(color:)` 合并到框架
        // 自己的默认样式上 ⇒ 字号/行高保持 ✓）；注入 `titleTextStyle` 会顶掉带度量的默认样式 ✗。
        listTileTheme: theme.listTileTheme.copyWith(textColor: gStyle.color),
      );
    }
    TextTheme? resolved;
    // ⚠️ 先拆空树：直接换主题会让 `ListTile` 内的 `AnimatedDefaultTextStyle` 在新旧样式间
    // 做隐式 lerp（两者 `inherit` 不同 ⇒ lerp 断言失败 ✗）⇒ 两态必须各自**独立建树** ✓。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          theme: theme,
          builder: (context, child) {
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
    appdata.settings[followKey] = true;
    final on = await pipeline(tester);
    // 未设颜色时主题字号必须存在（否则守护本身失效 ✗）
    expect(on['bodyLarge.size'], isNotNull);
    expect(on['rowStyle'], contains('size=16.0'));

    appdata.settings[textKey] = '#7B1FA2';
    appdata.settings[followKey] = false;
    final off = await pipeline(tester);

    expect(off, on, reason: '只改文字颜色不允许改动任何字体度量或渲染尺寸');
    expect(
      off['bodyLarge.size'],
      isNotNull,
      reason: '注入不得清空主题字号（TextStyle.apply 陷阱）',
    );
  });

  testWidgets('T-GTS2 未设颜色但设了字体 ⇒ 字体族随设置变化且字号不变', (tester) async {
    appdata.settings[textKey] = 'system';
    final none = await pipeline(tester);
    appdata.settings[familyKey] = 'SimHei';
    expect(globalFontFamily(), 'SimHei');
    final fonted = await pipeline(tester);
    expect(
      fonted['bodyMedium.size'],
      none['bodyMedium.size'],
      reason: '换字体不得改字号',
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
    appdata.settings['globalFontFile'] = '';
    appdata.settings[scaleKey] = 1;
    appdata.settings[textKey] = '#123456';

    appdata.settings[followKey] = true;
    final on = await pipeline(tester);

    appdata.settings[followKey] = false;
    expect(globalFontFamily(), isNull, reason: '空字符串必须等价于"未设置"');
    final off = await pipeline(tester);

    expect(off, on, reason: '只切总开关不允许改动任何字体度量或渲染尺寸');
  });
}
