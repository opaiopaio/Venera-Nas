import 'dart:io';

import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
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

/// ⭐ Y1（用户反馈 ✓）：**跟随系统主题**（=「窗口与控件」总开关关闭 ✓）时，
/// **忽略直角/圆角设置** ✗ → 恒用**默认圆角**（`AppRadius.lg` = 12 ✓）。
/// 用户原话 ✓："窗口与控件的设置在关闭之后，直角圆角的遮罩控制会被**保留** ✗，
/// 而不是回到默认状态 ✓，我想要关闭之后默认为**圆角**遮罩 ✓"。
double windowOverlayRadius() {
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return AppRadius.lg; // 默认圆角 ✓
  }
  return (appdata.settings['windowOverlayCorner'] as String? ?? 'rounded') ==
          'square'
      ? AppRadius.none
      : AppRadius.lg;
}

/// 「窗口/按钮背景」的圆角（未启用时返回 null，保持原样式）。
/// ⭐ Y1：跟随主题时同样**恒为默认圆角** ✓（忽略 `windowOverlayCorner` 设置 ✗）。
BorderRadius? windowOverlayBorderRadius() {
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return BorderRadius.circular(AppRadius.lg);
  }
  return appdata.settings.cornerStyleActive
      ? BorderRadius.circular(windowOverlayRadius())
      : null;
}

/// 「窗口/按钮背景」色 —— **独立于主题色**，单独配置：
/// - `transparent` → 透明（无填充）
/// - `system` → 跟随系统（中性容器色 `surfaceContainerHigh`，取缓存）
/// - `#RRGGBB` → 指定色
/// 最后乘以「窗口/按钮背景不透明度」。
///
/// 性能：结果按「设置值 + 不透明度 + 系统色缓存」做了缓存 —— 该方法被 35+ 处、
/// 每帧 build 调用，避免重复解析与 `Color` 分配。
Color windowOverlayColor() {
  // ⭐ N1：该页总开关「跟随系统主题」开启时 ✗ → 遮罩**完全不参与** ✓（等价于最初的干净默认 ✓）
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return Colors.transparent;
  }
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

/// ⭐ H3（2026-10-08）：**按钮背景**的统一入口 ✓ —— 与「窗口背景」**分离** ✓。
///
/// 原先面板与按钮都用 `windowOverlayColor()` ✗（像素级完全相同 ✓）→
/// 按钮叠在同色面板上**完全融合** ✗（用户实测反馈："窗口和按钮的颜色和透明度
/// 融合在一起" ✓）。
///
/// 规则 ✓：
/// - **颜色**：优先设置项 `buttonOverlayColor` ✓（`system` = **跟随窗口色** ✓ /
///   `transparent` / `#RRGGBB`）；未设置 → 跟随窗口色 ✓（**颜色零回归** ✓）。
/// - **不透明度**：优先设置项 `buttonOverlayOpacity` ✓（0..1，clamp ✓）；
///   未设置 → **自动加强一档** ✓ = `min(1.0, 窗口不透明度 + 0.3)` ✓
///   → 默认状态下按钮就比面板更实 ✓，不再融合 ✓（想恢复融合：把该值调成与窗口一致 ✓）。
Color buttonOverlayColor() {
  // ⭐ O1（用户澄清 ✓）：跟随主题时**不是透明** ✗ —— 最初默认下胶囊按钮本就有**主题色底** ✓
  //（只有窗口/图标按钮才是透明 ✓）。主题色由 `main.dart` 的 `getTheme()` 写入本缓存 ✓
  //（helpers 无 BuildContext ✗ → 沿用 `systemContainerColorCache` 的既有模式 ✓）。
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return themeButtonColorCache ?? Colors.transparent;
  }
  final v = (appdata.settings['buttonOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;

  final rawOpacity = (appdata.settings['buttonOverlayOpacity'] as num?)
      ?.toDouble();
  double opacity;
  if (rawOpacity != null) {
    opacity = rawOpacity.clamp(0.0, 1.0);
  } else {
    final winOpacity =
        ((appdata.settings['windowOverlayOpacity'] as num?)?.toDouble() ?? 1.0)
            .clamp(0.0, 1.0);
    // 自动加强一档 ✓（+0.3，上限 1.0 ✓）
    opacity = (winOpacity + 0.3).clamp(0.0, 1.0);
  }
  if (opacity <= 0) return Colors.transparent;

  // ⭐ M2（用户指正 ✓）：`system` = **跟随系统容器色** ✓ —— 与「窗口背景色」的 system
  // 语义完全一致 ✓（原先我让它跟随"窗口色" ✗ → 语义不自洽 ✗，且窗口设为 transparent 时
  // 按钮会跟着透明 ✗）。现在四项（窗口 / 胶囊 / 图标 / 标签）**各自独立** ✓：
  // `system` 都取系统容器色 ✓，互不干扰 ✓。
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  final base = n == null
      ? (systemContainerColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  return base.toOpacity(opacity);
}

/// ⭐ J1（2026-10-08）：**图标按钮背景**的统一入口 ✓ —— 与「胶囊按钮」**独立** ✓。
///
/// 用户诉求 ✓："把图标按钮的遮罩和胶囊按钮也分离，既然做自定义那就让大伙来选，
/// 透明度也一样" ✓ → 图标按钮（只有图标的按钮 ✓：顶栏动作按钮 / `IconButton` /
/// 页面右上「⋯」✓）拥有**自己的**颜色与不透明度设置 ✓。
///
/// 规则 ✓：
/// - **颜色** `iconOverlayColor`：`system`（**默认** ✓）= **跟随胶囊按钮色** ✓ /
///   `transparent` / `#RRGGBB` ✓；
/// - **不透明度** `iconOverlayOpacity`：0..1 ✓（**默认 0.85** ✓ 与胶囊默认一致 ✓）；
/// - 两者默认都与胶囊按钮一致 ✓ → **开箱零视觉变化** ✓，用户可随后各自调开 ✓。
///
/// ⚠️ `Color.toOpacity()` 是**替换 alpha** ✓（不是相乘 ✓）→ 可直接在"跟随胶囊"
/// 的基色上套用**图标自己的**不透明度 ✓。
Color iconOverlayColor() {
  // N1：总开关跟随主题 → 不参与 ✓
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return Colors.transparent;
  }
  final v = (appdata.settings['iconOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;

  final opacity =
      ((appdata.settings['iconOverlayOpacity'] as num?)?.toDouble() ?? 0.85)
          .clamp(0.0, 1.0);
  if (opacity <= 0) return Colors.transparent;

  // ⭐ M2：`system` = 跟随**系统容器色** ✓（与其它三项一致 ✓，**不再**跟随胶囊按钮 ✗）。
  // 想与胶囊按钮同色 → 把颜色显式设成同一值 ✓。
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  final base = n == null
      ? (systemContainerColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  return base.toOpacity(opacity);
}

/// ⭐ K1（2026-10-08）：**标签（tag/chip）背景**的统一入口 ✓ —— 与「窗口」「按钮」「图标按钮」都**独立** ✓。
///
/// 用户诉求 ✓："标签颜色也单独做一个选项，可以设置颜色和透明度，就和按钮遮罩一样，
/// 放在窗口和控件分类下面" ✓。
///
/// 与外观页「标签颜色」开关（`tagColorMode`）的关系 ✓：
/// - `tagColorMode == 'theme'` → 用 `colorScheme.secondaryContainer` ✓（**不走**本函数 ✓）；
/// - `tagColorMode == 'overlay'`（默认 ✓）→ 用**本函数** ✓。
///
/// 规则 ✓：
/// - **颜色** `tagOverlayColor`：`system`（**默认** ✓）= 跟随**窗口**色 ✓
///   （与旧 `overlay` 行为一致 ✓ 颜色零回归 ✓）/ `transparent` / `#RRGGBB` ✓；
/// - **不透明度** `tagOverlayOpacity`：0..1 ✓（**默认 0.85** ✓，与按钮/图标按钮默认一致 ✓）。
Color tagOverlayColor() {
  // ⭐ O1：同 `buttonOverlayColor()` ✓ —— 跟随主题时取**主题色** ✓（不是透明 ✗）
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    return themeButtonColorCache ?? Colors.transparent;
  }
  final v = (appdata.settings['tagOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;

  final opacity =
      ((appdata.settings['tagOverlayOpacity'] as num?)?.toDouble() ?? 0.85)
          .clamp(0.0, 1.0);
  if (opacity <= 0) return Colors.transparent;

  // ⭐ M2：`system` = 跟随**系统容器色** ✓（与其它三项一致 ✓，**不再**跟随窗口色 ✗）。
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  final base = n == null
      ? (systemContainerColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  return base.toOpacity(opacity);
}

/// 「窗口/按钮背景」的统一方框：启用遮罩时包一层圆角底色（用 `Material` 裁切，
/// 保证 `InkWell` 墨水也跟随圆角）；未启用时原样返回，零回归。
class WindowOverlayBox extends StatelessWidget {
  const WindowOverlayBox({required this.child, this.margin, super.key});

  final Widget child;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：设置变化时由框架**精准重建本控件**
    // （取代 `App.forceRebuild()` 的整树 markNeedsBuild 遍历，后者会导致鬼影）。
    AppSettingsScope.of(context);
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
/// ⭐ P2（用户反馈 ✓）：**跟随系统主题**时恒为 null ✓ —— 既不做图片切片 ✓，也不带加深色调 ✓；
/// 这种情况下由 `SecondaryPageSurface` 补一层**主题表面色** ✓（遮挡 ✓、不调色 ✓）。
BoxDecoration? secondaryPageDecoration() {
  if (appdata.settings['secondaryPageFollowTheme'] == true) return null;
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
/// ⭐ O1：**主题色缓存** ✓ —— 由 `main.dart` 的 `getTheme()` 写入（`scheme.secondaryContainer` ✓），
/// 供"跟随系统主题"时的**胶囊按钮/标签**底色使用 ✓（helpers 无 BuildContext ✗ → 沿用
/// `systemContainerColorCache` 的既有模式 ✓）。
Color? themeButtonColorCache;

/// ⭐ AF1：**顶栏「漫画源」按钮**（分类/发现页顶部那一排 ✓，含「+ 加号」✓）的**主题色缓存** ✓ ——
/// 由 `main.dart` 的 `getTheme()` 写入 `scheme.secondaryContainer` ✓（= 现状外观 ✓ 零回归 ✓）。
Color? themeSourceTabColorCache;

/// ⭐ AF1（用户要求 ✓）：顶栏「分类/发现页顶部**漫画源按钮**」的统一入口 ✓。
///
/// - **颜色** `sourceTabOverlayColor`：`system`（默认 ✓）= 跟随**主题**（`secondaryContainer` ✓，
///   即用户现有观感 ✓ 零回归 ✓）/ `transparent`（透明 ✓）/ `#RRGGBB`（自定义 ✓）；
/// - **不透明度** `sourceTabOverlayOpacity`：0..1 ✓（默认 1 ✓）；
/// - 受「窗口与控件」总开关管理 ✓：`windowOverlayFollowTheme == true`（跟随主题 ✓）时
///   恒取 `secondaryContainer` ✓，与其它遮罩（窗口/胶囊/图标按钮/标签 ✓）逻辑一致 ✓。
Color sourceTabOverlayColor() {
  if (appdata.settings['windowOverlayFollowTheme'] == true) {
    // ⭐ AG1（用户澄清 ✓）：**跟随系统 = 系统的「按钮」颜色** ✓ ——
    // 即胶囊按钮在跟随主题时所用的 `themeButtonColorCache`（`secondaryFixed` ✓），
    // **不是**主题容器色 `secondaryContainer` ✗（用户原话："跟随系统是用系统的按钮颜色 ✓，
    // 懂吗，不是系统主题色 ✗"）。
    return themeButtonColorCache ?? Colors.transparent;
  }
  final v = (appdata.settings['sourceTabOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;
  final opacity =
      ((appdata.settings['sourceTabOverlayOpacity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.0, 1.0);
  if (opacity <= 0) return Colors.transparent;
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  // `system` 同样 = **系统按钮色** ✓（与总开关开启时一致 ✓）。
  final base = n == null
      ? (themeButtonColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  return base.toOpacity(opacity);
}

Color? customSecondarySurfaceColor(ColorScheme scheme) {
  // ⭐ O1（用户澄清 ✓）：二级页面「跟随系统主题」时**只让色调不生效** ✓ ——
  // 默认态必须**不做色调调整** ✓，但**遮挡下面内容** ✓（`secondaryPageFeatureActive` 仍为 true ✓）
  // 且**突出二级菜单** ✓（`secondaryMenuDim` 默认 true ✓）都属于"回到最初默认" ✓。
  if (appdata.settings['secondaryPageFollowTheme'] == true) return null;
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
  // ① **有背景图** ✓ → 底由**壁纸切片**（`BackgroundSlice`）负责 ✓，
  //    本函数只给"切片之上的色调遮罩" ✓（原语义 ✓，色调作用于**壁纸** ✓）。
  if (currentBackgroundImageFile() != null) return tintColor;
  // ② **无背景图** ✓ → **以当前背景色为主** ✓：把深浅直接调在**背景色**上 ✓
  //（用户截图澄清 ✓：背景是**明黄色**，弹层应是"**明黄稍深**"✓，绝不能是**黑色遮罩** ✗）。
  final baseValue = appdata.settings.customBackgroundBaseColorValue;
  final base = baseValue != null ? Color(baseValue) : scheme.surface;
  final blended = Color.alphaBlend(tintColor, base);
  // ③ **半透明模式** ✓ → 同一"背景色 ± 深浅"的成品色再给透明度 ✓
  //（仍是"背景色稍深"的半透面板 ✓，而不是裸黑/白遮罩 ✗）。
  return mode == 'transparent'
      ? blended.withValues(alpha: AppOpacity.hint)
      : blended;
}
