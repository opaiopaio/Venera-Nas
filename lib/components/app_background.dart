part of 'components.dart';

/// 窗口/栏背景色（顶栏、侧栏、页面底、设置左栏等）：
/// 自定义背景启用时返回透明（让背景透出），否则返回 [fallback]。
Color? customBackgroundAware(Color? fallback) =>
    appdata.settings.backgroundFeatureActive ? Colors.transparent : fallback;

/// 「窗口/按钮背景」的圆角半径：`rounded`（默认，12）/ `square`（0，直角）。
double windowOverlayRadius() =>
    (appdata.settings['windowOverlayCorner'] as String? ?? 'rounded') == 'square'
    ? 0
    : 12;

/// 「窗口/按钮背景」的圆角（未启用时返回 null，保持原样式）。
BorderRadius? windowOverlayBorderRadius() =>
    appdata.settings.cornerStyleActive
    ? BorderRadius.circular(windowOverlayRadius())
    : null;

/// 「窗口/按钮背景」的统一方框：配置了遮罩时包一层圆角底色（用 `Material` 裁切，
/// 保证 `InkWell` 墨水也跟随圆角）；未配置时原样返回，零回归。
class WindowOverlayBox extends StatelessWidget {
  const WindowOverlayBox({required this.child, this.margin, super.key});

  final Widget child;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    if (!appdata.settings.hasWindowOverlay) return child;
    return Padding(
      padding:
          margin ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: windowOverlayColor(),
        borderRadius: windowOverlayBorderRadius(),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// 「窗口遮罩」色：用于**卡片/窗口类容器**（首页分区卡片、收藏文件夹卡片等）的填充。
/// 由「窗口遮罩颜色 / 窗口遮罩不透明度」配置，默认透明（等同原来的只有描边）。
/// 未启用自定义背景时同样返回透明，不影响原有效果。
/// 系统容器色缓存：由 `getTheme()` 在构建主题时写入。
/// ⚠️ 不能在 `getTheme()` 里调用 `Theme.of(...)`（主题尚未建立会导致启动异常），
/// 因此这里缓存一份供 `windowOverlayColor()` 使用。
Color? systemContainerColorCache;

/// 「窗口/按钮背景」色 —— **独立于主题色**，单独配置：
/// - `transparent` → 透明（无填充）
/// - `system` → 跟随系统（主题容器色，取缓存，避免在 getTheme 里 Theme.of）
/// - `#RRGGBB` → 指定色
/// 最后乘以「窗口/按钮背景不透明度」。
Color windowOverlayColor() {
  final v = (appdata.settings['windowOverlayColor'] ?? 'system').toString();
  if (v == 'transparent') return Colors.transparent;
  final opacity =
      ((appdata.settings['windowOverlayOpacity'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.0, 1.0);
  if (opacity <= 0) return Colors.transparent;
  final n = (v.startsWith('#') && v.length == 7)
      ? int.tryParse(v.substring(1), radix: 16)
      : null;
  final base = n == null
      ? (systemContainerColorCache ?? Colors.transparent)
      : Color(0xFF000000 | n);
  return base.toOpacity(opacity);
}

/// 二级页面（弹层）的背景装饰：**有背景图时以背景图为准**（图优先于背景色），
/// 仅在「不透明」样式下返回；返回 null 表示不做图片装饰。
BoxDecoration? secondaryPageDecoration() {
  if (!appdata.settings.secondaryPageFeatureActive) return null;
  final mode = appdata.settings['secondaryPageMode'] as String? ?? 'opaque';
  if (mode == 'transparent') return null;
  final file = AppBackground.currentImageFile();
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
      fit: AppBackground.boxFitOf(fit),
    ),
  );
}

/// 二级页面（弹层）的表面色（`Material` 颜色）：
/// - 未启用自定义背景 → null（保持原行为）
/// - `transparent` 样式 → 半透明黑/白（下层内容透出来）
/// - `opaque` 样式 → 有背景图时返回**叠在背景图之上的半透明黑/白**（图本身不透明，
///   合成后整体不透明、完全遮住下层）；无背景图时按**背景色**加深/变浅得到不透明色。
Color? customSecondarySurfaceColor(ColorScheme scheme) {
  if (!appdata.settings.secondaryPageFeatureActive) return null;
  final mode = appdata.settings['secondaryPageMode'] as String? ?? 'opaque';
  final tint = appdata.settings['secondaryPageTint'] as String? ?? 'darken';
  final strength =
      ((appdata.settings['secondaryPageTintStrength'] as num?)?.toDouble() ??
              0.22)
          .clamp(0.0, 1.0);
  final tintColor = switch (tint) {
    'lighten' => Colors.white.toOpacity(strength),
    'darken' => Colors.black.toOpacity(strength),
    _ => Colors.transparent,
  };
  if (mode == 'transparent') return tintColor;
  if (AppBackground.currentImageFile() != null) return tintColor;
  final baseValue = appdata.settings.customBackgroundBaseColorValue;
  final base = baseValue != null ? Color(baseValue) : scheme.surface;
  return Color.alphaBlend(tintColor, base);
}

/// 全局自定义背景层：底色（可配置）+ 可选图片（透明度 / 显示方式）。
///
/// 由 `main.dart` 的 `MaterialApp.builder` 垫在所有内容之下。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  /// 背景图片存放目录。
  static String get _imageDir => '${App.dataPath}/background';

  /// 图片绝对路径（[name] 为文件名）。
  static String? imagePath(String? name) {
    if (name == null || name.isEmpty) return null;
    return '$_imageDir/$name';
  }

/// 是否启用了自定义背景（有图片 或 底色非透明）。
  static bool get isActive => appdata.settings.backgroundFeatureActive;

  /// 当前背景图片文件（未设置或文件不存在时返回 null）。
  static File? currentImageFile() {
    final name = appdata.settings['backgroundImage'] as String? ?? '';
    final path = imagePath(name);
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  static BoxFit boxFitOf(String fit) => switch (fit) {
    'contain' => BoxFit.contain,
    'fill' => BoxFit.fill,
    'fitWidth' => BoxFit.fitWidth,
    'fitHeight' => BoxFit.fitHeight,
    'none' => BoxFit.none,
    'scaleDown' => BoxFit.scaleDown,
    _ => BoxFit.cover,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColorValue =
        appdata.settings['backgroundColor'] as String? ?? 'transparent';
    final base = resolveColorSettingValue(bgColorValue) ?? scheme.surface;
    final imageName = appdata.settings['backgroundImage'] as String? ?? '';
    final opacity =
        ((appdata.settings['backgroundImageOpacity'] as num?)?.toDouble() ??
                1.0)
            .clamp(0.0, 1.0);
    final fit = appdata.settings['backgroundImageFit'] as String? ?? 'cover';

    Widget layer = ColoredBox(color: base);

    final path = imagePath(imageName);
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        Widget img;
        if (fit == 'repeat') {
          img = DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: FileImage(file),
                repeat: ImageRepeat.repeat,
              ),
            ),
          );
        } else {
          img = Image.file(
            file,
            fit: boxFitOf(fit),
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
        layer = Stack(
          fit: StackFit.expand,
          children: [layer, Opacity(opacity: opacity, child: img)],
        );
      }
    }
    return layer;
  }
}
