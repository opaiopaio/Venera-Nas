import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/appdata.dart';

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
  final v = (appdata.settings['globalTextColor'] ?? 'system').toString();
  if (!v.startsWith('#') || v.length != 7) return null; // system / transparent
  return _parse(v, Colors.black);
}

/// 全局字体名；`null`/空 表示跟随系统。
String? globalFontFamily() {
  final v = (appdata.settings['globalFontFamily'] ?? '').toString();
  return (v.isEmpty || v == 'system') ? null : v;
}

/// 全局字号缩放（0.8 - 1.4，默认 1.0）。
double globalFontScale() =>
    ((appdata.settings['globalFontScale'] as num?)?.toDouble() ?? 1.0).clamp(
      0.8,
      1.4,
    );

/// 阴影 + 发光。发光用「多层同色、位移为 0、模糊递增」的 Shadow 叠加实现。
List<Shadow>? globalTextShadows() {
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
          color: color.withValues(
            alpha: strength * (1 - (i - 1) / 4) * 0.6,
          ),
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

/// 是否有任何全局文字设置被启用（用于按钮前景色等"全控制"注入）。
bool get globalTextActive =>
    globalTextStyle() != null || globalFontScale() != 1.0;

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
