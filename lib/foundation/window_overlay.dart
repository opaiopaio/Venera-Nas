import 'dart:io';

import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

/// 「窗口/按钮/选项背景」与全局背景相关的**通用 helper**。
///
/// 放在 `foundation` 层、且**不依赖 `components`**：
/// 这样 `foundation/widget_utils.dart` 等底层文件可以直接使用，
/// 避免 `foundation ↔ components` 的循环依赖。
///
/// 涉及三套**互相独立**的设置：
/// 1. 背景体系（背景图 / 底色）—— `Settings.backgroundFeatureActive`
/// 2. 窗口与控件（遮罩色 · 不透明度 · 圆角/直角）—— `Settings.hasWindowOverlay` / `cornerStyleActive`
/// 3. 二级页面（样式 / 色调 / 强度）—— `Settings.secondaryPageFeatureActive`

// ───────────────────────────── ① 背景体系 ─────────────────────────────

/// 窗口/栏背景色（顶栏、侧栏、页面底、设置左栏等）：
/// 背景体系启用时返回透明（让背景透出），否则返回 [fallback]。
Color? customBackgroundAware(Color? fallback) =>
    appdata.settings.backgroundFeatureActive ? Colors.transparent : fallback;

/// 全局背景图片目录。
String get backgroundImageDir => '${App.dataPath}/background';

/// 背景图片**绝对路径**（[name] 为文件名，空则返回 null）。
String? backgroundImagePath(String? name) {
  if (name == null || name.isEmpty) return null;
  return '$backgroundImageDir/$name';
}

/// 当前背景图片文件（未设置或文件不存在时返回 null）。
File? currentBackgroundImageFile() {
  final path = backgroundImagePath(
    appdata.settings['backgroundImage'] as String? ?? '',
  );
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? file : null;
}

/// 「图片显示方式」设置 → [BoxFit]。
BoxFit backgroundBoxFitOf(String fit) => switch (fit) {
  'contain' => BoxFit.contain,
  'fill' => BoxFit.fill,
  'fitWidth' => BoxFit.fitWidth,
  'fitHeight' => BoxFit.fitHeight,
  'none' => BoxFit.none,
  'scaleDown' => BoxFit.scaleDown,
  _ => BoxFit.cover,
};

// ───────────────────────── ② 窗口与控件（遮罩）─────────────────────────

/// 系统容器色缓存：由 `getTheme()` 在构建主题时写入。
///
/// ⚠️ 不能在 `getTheme()` 里调用 `Theme.of(...)`（主题尚未建立会导致启动异常），
/// 因此缓存一份供 [windowOverlayColor] 使用。
Color? systemContainerColorCache;

/// 「窗口/按钮背景」的圆角半径：`rounded`（默认，12）/ `square`（0，直角）。
double windowOverlayRadius() =>
    (appdata.settings['windowOverlayCorner'] as String? ?? 'rounded') ==
        'square'
    ? AppRadius.none
    : AppRadius.lg;

/// 「窗口/按钮背景」的圆角（未启用时返回 null，保持原样式）。
BorderRadius? windowOverlayBorderRadius() => appdata.settings.cornerStyleActive
    ? BorderRadius.circular(windowOverlayRadius())
    : null;

/// 「窗口/按钮背景」色 —— **独立于主题色**，单独配置：
/// - `transparent` → 透明（无填充）
/// - `system` → 跟随系统（中性容器色 `surfaceContainerHigh`，取缓存）
/// - `#RRGGBB` → 指定色
/// 最后乘以「窗口/按钮背景不透明度」。
///
/// 性能：结果按「设置值 + 不透明度 + 系统色缓存」做了缓存 —— 该方法被 35+ 处、
/// 每帧 build 调用，避免重复解析与 `Color` 分配。
Color windowOverlayColor() {
  final v = (appdata.settings['windowOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;
  final opacity =
      ((appdata.settings['windowOverlayOpacity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.0, 1.0);
  if (opacity <= 0) return Colors.transparent;
  if (v == _cachedValue &&
      opacity == _cachedOpacity &&
      systemContainerColorCache == _cachedSystemColor) {
    return _cachedResult!;
  }
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  final base = n == null
      ? (systemContainerColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  _cachedValue = v;
  _cachedOpacity = opacity;
  _cachedSystemColor = systemContainerColorCache;
  _cachedResult = base.toOpacity(opacity);
  return _cachedResult!;
}

String? _cachedValue;
double? _cachedOpacity;
Color? _cachedSystemColor;
Color? _cachedResult;

/// 「窗口/按钮背景」的统一方框：启用遮罩时包一层圆角底色（用 `Material` 裁切，
/// 保证 `InkWell` 墨水也跟随圆角）；未启用时原样返回，零回归。
class WindowOverlayBox extends StatelessWidget {
  const WindowOverlayBox({required this.child, this.margin, super.key});

  final Widget child;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    if (!appdata.settings.hasWindowOverlay) return child;
    return Padding(
      padding:
          margin ??
          const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.xs,
          ),
      child: Material(
        color: windowOverlayColor(),
        borderRadius: windowOverlayBorderRadius(),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// 按需遮罩：`masked` 为 true 时包一层 [WindowOverlayBox]（与 `toSliver()` 同一入口，
/// 内边距 / 圆角 / 裁切完全一致），否则**原样返回**（零回归）。
///
/// 用途：那些**不经过 `toSliver()`** 的独立设置行（例如 `SliverAnimatedVisibility`
/// 内部的行、`Column` 里直接铺的行）需要显式声明 `masked: true` 才会被遮罩体系覆盖。
Widget maskIfNeeded(bool masked, Widget child, {EdgeInsetsGeometry? margin}) =>
    masked ? WindowOverlayBox(margin: margin, child: child) : child;

// ─────────────────────────── ③ 二级页面 ───────────────────────────

/// 二级页面（弹层）的背景装饰：**有背景图时以背景图为准**（图优先于背景色），
/// 仅在「不透明」样式下返回；返回 null 表示不做图片装饰。
BoxDecoration? secondaryPageDecoration() {
  if (!appdata.settings.secondaryPageFeatureActive) return null;
  final mode = appdata.settings['secondaryPageMode'] as String? ?? 'opaque';
  if (mode == 'transparent') return null;
  final file = currentBackgroundImageFile();
  if (file == null) return null;
  final fit = appdata.settings['backgroundImageFit'] as String? ?? 'cover';
  if (fit == 'repeat') {
    return BoxDecoration(
      image: DecorationImage(
        image: FileImage(file),
        repeat: ImageRepeat.repeat,
      ),
    );
  }
  return BoxDecoration(
    image: DecorationImage(
      image: FileImage(file),
      fit: backgroundBoxFitOf(fit),
    ),
  );
}

/// 二级页面（弹层）的表面色（`Material` 颜色）：
/// - 未启用 → null（保持原行为）
/// - `transparent` 样式 → 半透明黑/白（下层内容透出来）
/// - `opaque` 样式 → 有背景图时返回**叠在背景图之上的半透明黑/白**（图本身不透明，
///   合成后整体不透明、完全遮住下层）；无背景图时按**背景色**加深/变浅得到不透明色。
Color? customSecondarySurfaceColor(ColorScheme scheme) {
  if (!appdata.settings.secondaryPageFeatureActive) return null;
  final mode = appdata.settings['secondaryPageMode'] as String? ?? 'opaque';
  final tint = appdata.settings['secondaryPageTint'] as String? ?? 'darken';
  final strength =
      ((appdata.settings['secondaryPageTintStrength'] as num?)?.toDouble() ??
              AppOpacity.tintStrengthDefault)
          .clamp(0.0, 1.0);
  final tintColor = switch (tint) {
    'lighten' => Colors.white.toOpacity(strength),
    'darken' => Colors.black.toOpacity(strength),
    _ => Colors.transparent,
  };
  if (mode == 'transparent') return tintColor;
  if (currentBackgroundImageFile() != null) return tintColor;
  final baseValue = appdata.settings.customBackgroundBaseColorValue;
  final base = baseValue != null ? Color(baseValue) : scheme.surface;
  return Color.alphaBlend(tintColor, base);
}
