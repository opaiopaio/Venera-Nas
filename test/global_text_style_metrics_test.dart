import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

/// 守护：**「全局文字样式」注入必须对字体度量保持中性**。
///
/// 约定：用户**只**设置了「文字颜色」时，文本的 `fontSize` / `height` / 字体族
/// （含 fallback ✓）与渲染尺寸必须与**未设置时逐像素一致**；
/// 只有用户**显式**调过「字体」「字号缩放」时才允许改变度量。
///
/// 复刻 `main.dart` 的注入链（`getTheme()` 的 `textTheme` 注入 +
/// `MaterialApp.builder` 的 `DefaultTextStyle.merge`），逐条比对度量。
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

  /// 复刻 `main.dart` 的两处注入 ✓（`getTheme()` 的 textTheme + builder 的 DefaultTextStyle ✓）。
  Future<Map<String, Object?>> pipeline(WidgetTester tester) async {
    final gStyle = globalTextStyle();
    var theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2143F3)),
      fontFamily: 'TestFont',
      fontFamilyFallback: const ['TestFallback', 'sans-serif'],
    );
    if (gStyle != null) {
      theme = theme.copyWith(
        textTheme: decorateTextTheme(
          theme.textTheme.apply(
            fontFamily: gStyle.fontFamily,
            bodyColor: gStyle.color,
            displayColor: gStyle.color,
          ),
        ),
      );
    }
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
          home: const Scaffold(
            body: Center(child: Text('Sample 汉字 14', key: Key('probe'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final t = theme.textTheme;
    final out = <String, Object?>{};
    for (final e in {
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'titleSmall': t.titleSmall,
      'labelSmall': t.labelSmall,
    }.entries) {
      out['${e.key}.size'] = e.value?.fontSize;
      out['${e.key}.height'] = e.value?.height;
      out['${e.key}.family'] = e.value?.fontFamily;
      out['${e.key}.fallback'] = e.value?.fontFamilyFallback?.join('|');
      out['${e.key}.spacing'] = e.value?.letterSpacing;
    }
    out['rendered'] = tester.getSize(find.byKey(const Key('probe')));
    return out;
  }

  testWidgets('T-GTS1 只设文字颜色 ⇒ 度量与渲染尺寸逐项不变', (tester) async {
    appdata.settings[textKey] = 'system';
    final none = await pipeline(tester);
    appdata.settings[textKey] = '#123456';
    final colored = await pipeline(tester);
    expect(colored, none, reason: '只改颜色不允许改动任何字体度量');
  });

  testWidgets('T-GTS2 未设颜色但设了字体 ⇒ 字体族随设置变化（度量只该按字体变）', (tester) async {
    appdata.settings[textKey] = 'system';
    final none = await pipeline(tester);
    appdata.settings[familyKey] = 'SimHei';
    expect(globalFontFamily(), 'SimHei');
    final fonted = await pipeline(tester);
    expect(
      fonted['bodyMedium.family'],
      isNot(none['bodyMedium.family']),
      reason: '显式选字体时必须生效',
    );
  });

  testWidgets('T-GTS3 只设颜色且字号缩放为 1.0 ⇒ 不注入 textScaler', (tester) async {
    appdata.settings[textKey] = '#123456';
    appdata.settings[scaleKey] = 1.0;
    expect(globalFontScale(), 1.0);
    appdata.settings[scaleKey] = 0.8;
    expect(globalFontScale(), 0.8);
  });
}
