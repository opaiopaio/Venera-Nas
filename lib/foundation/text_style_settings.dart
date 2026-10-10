import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

/// 全局文字样式（颜色 / 字体 / 阴影 / 发光 / 字号缩放）。
///
/// 与「自定义背景」搭配使用：暗色背景时把文字统一改成亮色，避免看不清。
/// 放在 `foundation` 层且不依赖 `components`。
///
/// 注入点：
/// - `main.dart` 的 `getTheme()` → `textTheme` + 各按钮主题的 `foregroundColor`（全控制）
/// - `main.dart` 的 `MaterialApp.builder` → `DefaultTextStyle.merge` + `TextScaler`

Color _parse(String? value, Color fallback) {
  if (value == null || !value.startsWith('#') || value.length != 7) {
    return fallback;
  }
  final n = int.tryParse(value.substring(1), radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

/// 全局字体颜色；`null` 表示跟随系统（不覆盖）。
Color? globalTextColor() {
  // ⭐ N1：文字页总开关「跟随系统主题」开启时 ✗ → 不注入任何颜色 ✓（回到主题默认 ✓）
  if (appdata.settings['textFollowTheme'] == true) return null;
  final v = (appdata.settings['globalTextColor'] ?? 'system').toString();
  if (!v.startsWith('#') || v.length != 7) return null; // system / transparent
  return _parse(v, Colors.black);
}

/// 自定义字体目录 / 文件绝对路径。
String get customFontDir => '${App.dataPath}/fonts';

String? customFontPath(String? name) =>
    (name == null || name.isEmpty) ? null : '$customFontDir/$name';

/// 运行期加载成功的自定义字体族名（`loadCustomFont()` 写入）。
String? customFontFamilyName;

/// 运行期加载自定义字体文件（ttf/otf/ttc）。
///
/// 应用启动、切换字体、导入备份后都应调用一次。
Future<void> loadCustomFont() async {
  customFontFamilyName = null;
  final name = (appdata.settings['globalFontFile'] ?? '').toString();
  final path = customFontPath(name);
  if (path == null) return;
  final file = File(path);
  if (!file.existsSync()) return;
  try {
    final bytes = await file.readAsBytes();
    // 族名必须**每次唯一**：`FontLoader` 用同一个族名重复注册时，引擎可能仍命中
    // 已注册的旧字体 → 表现为"换了自定义字体不生效"（与换背景图同类的缓存问题）。
    final family = 'VeneraCustomFont_${DateTime.now().millisecondsSinceEpoch}';
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
    customFontFamilyName = family;
  } catch (_) {
    customFontFamilyName = null;
  }
}

/// 全局字体名；`null`/空 表示跟随系统。
/// 优先使用**已加载的自定义字体文件**，其次才是系统字体名。
String? globalFontFamily() {
  // ⭐ N1：文字页总开关「跟随系统主题」开启时 ✗ → 不注入自定义字体 ✓（回到系统字体 ✓）
  if (appdata.settings['textFollowTheme'] == true) return null;
  if (customFontFamilyName != null) return customFontFamilyName;
  final v = (appdata.settings['globalFontFamily'] ?? '').toString();
  return (v.isEmpty || v == 'system') ? null : v;
}

/// 全局字号缩放（0.8 - 1.4，默认 1.0）。
double globalFontScale() {
  // ⭐ N1：文字页总开关「跟随系统主题」开启时 ✗ → 不缩放 ✓（回到最初默认字号 ✓）
  if (appdata.settings['textFollowTheme'] == true) return 1.0;
  return ((appdata.settings['globalFontScale'] as num?)?.toDouble() ?? 1.0)
      .clamp(AppTextScale.min, AppTextScale.max);
}

/// 阴影 + 发光。发光用「多层同色、位移为 0、模糊递增」的 Shadow 叠加实现。
List<Shadow>? globalTextShadows() {
  // ⭐ N1：文字页总开关「跟随系统主题」开启时 ✗ → 无阴影/发光 ✓（回到主题默认 ✓）
  if (appdata.settings['textFollowTheme'] == true) return null;
  final shadows = <Shadow>[];
  if (appdata.settings['textShadowEnabled'] == true) {
    shadows.add(
      Shadow(
        color: _parse(
          appdata.settings['textShadowColor'] as String?,
          Colors.black,
        ),
        blurRadius:
            ((appdata.settings['textShadowBlur'] as num?)?.toDouble() ?? 2.0)
                .clamp(0.0, 10.0),
        offset: Offset(
          ((appdata.settings['textShadowOffsetX'] as num?)?.toDouble() ?? 0.0)
              .clamp(-4.0, 4.0),
          ((appdata.settings['textShadowOffsetY'] as num?)?.toDouble() ?? 1.0)
              .clamp(-4.0, 4.0),
        ),
      ),
    );
  }
  if (appdata.settings['textGlowEnabled'] == true) {
    final color = _parse(
      appdata.settings['textGlowColor'] as String?,
      Colors.white,
    );
    final radius =
        ((appdata.settings['textGlowRadius'] as num?)?.toDouble() ?? 4.0).clamp(
          0.0,
          20.0,
        );
    final strength =
        ((appdata.settings['textGlowStrength'] as num?)?.toDouble() ?? 0.8)
            .clamp(0.0, 1.0);
    // 4 层递增，营造柔和的发光边缘（层数上限固定，控制绘制开销）。
    for (var i = 4; i >= 1; i--) {
      shadows.add(
        Shadow(
          color: color.withValues(alpha: strength * (1 - (i - 1) / 4) * 0.6),
          blurRadius: radius * i / 4,
        ),
      );
    }
  }
  return shadows.isEmpty ? null : shadows;
}

/// 全局文字样式；返回 `null` 表示未配置（此时完全不干预，零回归）。
TextStyle? globalTextStyle() {
  final color = globalTextColor();
  final family = globalFontFamily();
  final shadows = globalTextShadows();
  if (color == null && family == null && shadows == null) return null;
  return TextStyle(color: color, fontFamily: family, shadows: shadows);
}

/// 把「前景色 + 字体族」注入整套 [TextTheme]，**逐字段保留原有度量** ✓。
///
/// ⚠️ **不要**改用 `TextTheme.apply(...)` ✗：Flutter 的 `TextStyle.apply` 生成结果时
/// `fontSize` / `letterSpacing` / `wordSpacing` / `height` 取的是**该方法的参数**、不是 `this.*` ✗
///（`painting/text_style.dart`）⇒ 只传颜色/字体时会**把整套主题文字的字号与行高清空** ✗
/// ⇒ 表现：**显式写死字号**的标题（`ts.s18` 等 ✓）不变 ✗，而**继承主题字号**的选项行文字
///（`ListTile` 标题等 ✓）塌回环境默认 ⇒ "只改了文字颜色，选项文字却变小" ✗。
TextTheme applyTextThemeOverrides(
  TextTheme base, {
  Color? color,
  String? fontFamily,
}) {
  // `merge` 只覆盖**非 null** 字段 ⇒ 字号/行高/字距等一律原样保留 ✓。
  TextStyle? m(TextStyle? s) =>
      s?.merge(TextStyle(color: color, fontFamily: fontFamily));
  return base.copyWith(
    displayLarge: m(base.displayLarge),
    displayMedium: m(base.displayMedium),
    displaySmall: m(base.displaySmall),
    headlineLarge: m(base.headlineLarge),
    headlineMedium: m(base.headlineMedium),
    headlineSmall: m(base.headlineSmall),
    titleLarge: m(base.titleLarge),
    titleMedium: m(base.titleMedium),
    titleSmall: m(base.titleSmall),
    bodyLarge: m(base.bodyLarge),
    bodyMedium: m(base.bodyMedium),
    bodySmall: m(base.bodySmall),
    labelLarge: m(base.labelLarge),
    labelMedium: m(base.labelMedium),
    labelSmall: m(base.labelSmall),
  );
}

/// ⭐ 把「全局文字样式」注入 `ThemeData` —— **只改颜色/字体/阴影，绝不改任何度量** ✓。
///
/// 从 `main.dart` 的 `getTheme()`（App State 的**实例方法** ⇒ 单测调不到 ✗）抽到本层 ✓，
/// 让守护测试能**直接调它**并断言真实渲染尺寸 ✓（同 `applySystemContainerColorFor` 的先例 ✓）。
///
/// 落点 ✓：
/// - `textTheme` / `primaryTextTheme`：走 [applyTextThemeOverrides]（度量中性 ✓）+ [decorateTextTheme]（阴影/发光 ✓）；
/// - `listTileTheme`：**只注入 `textColor`** ✓ —— ⚠️ **不要**注入从 `theme.textTheme` 派生的
///   `titleTextStyle`/`subtitleTextStyle` ✗：`ThemeData.textTheme` 的各样式在树外**不含度量**
///   （`fontSize`/`height`/`letterSpacing` 为 `null` ✓，真实度量由 `MaterialApp` 侧补全 ✓）⇒
///   塞进 `ListTileThemeData` 会**顶掉** `ListTile` 带度量的默认样式 ⇒ 设置页**选项行 16 → 14** ✗
///   （大标题用显式 `ts.s18` ⇒ 不变 ✓ ⇒ 现象正是"只有选项文字变小" ✓）。
ThemeData applyGlobalTextStyleToTheme(ThemeData theme) {
  final style = globalTextStyle();
  if (style == null) return theme;
  final color = style.color;
  return theme.copyWith(
    textTheme: decorateTextTheme(
      applyTextThemeOverrides(
        theme.textTheme,
        color: color,
        fontFamily: style.fontFamily,
      ),
    ),
    primaryTextTheme: decorateTextTheme(
      applyTextThemeOverrides(
        theme.primaryTextTheme,
        color: color,
        fontFamily: style.fontFamily,
      ),
    ),
    listTileTheme: theme.listTileTheme.copyWith(textColor: color),
  );
}

/// 把全局文字样式（颜色/字体/**阴影+发光**）合并进整套 [TextTheme]。
///
/// 必要性：`DefaultTextStyle` 只能覆盖 `Text` 这类默认样式文本；
/// 按钮、标签栏、列表项等控件的文字来自**主题文字样式**，必须在这里注入，
/// 否则它们的阴影/发光不会生效。
TextTheme decorateTextTheme(TextTheme base) {
  final style = globalTextStyle();
  if (style == null) return base;
  TextStyle? m(TextStyle? s) => s?.merge(style);
  return base.copyWith(
    displayLarge: m(base.displayLarge),
    displayMedium: m(base.displayMedium),
    displaySmall: m(base.displaySmall),
    headlineLarge: m(base.headlineLarge),
    headlineMedium: m(base.headlineMedium),
    headlineSmall: m(base.headlineSmall),
    titleLarge: m(base.titleLarge),
    titleMedium: m(base.titleMedium),
    titleSmall: m(base.titleSmall),
    bodyLarge: m(base.bodyLarge),
    bodyMedium: m(base.bodyMedium),
    bodySmall: m(base.bodySmall),
    labelLarge: m(base.labelLarge),
    labelMedium: m(base.labelMedium),
    labelSmall: m(base.labelSmall),
  );
}
