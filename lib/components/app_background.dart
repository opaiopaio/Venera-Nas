part of 'components.dart';

/// 全局自定义背景层：底色（可配置）+ 可选图片（透明度 / 显示方式）。
///
/// 由 `main.dart` 的 `MaterialApp.builder` 垫在所有内容之下。
/// 遮罩/圆角等通用 helper 见 `foundation/window_overlay.dart`。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  /// 图片绝对路径（[name] 为文件名）。
  static String? imagePath(String? name) => backgroundImagePath(name);

  /// 是否启用了自定义背景（有图片 或 底色非透明）。
  static bool get isActive => appdata.settings.backgroundFeatureActive;

  /// 当前背景图片文件（未设置或文件不存在时返回 null）。
  static File? currentImageFile() => currentBackgroundImageFile();

  static BoxFit boxFitOf(String fit) => backgroundBoxFitOf(fit);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColorValue =
        appdata.settings['backgroundColor'] as String? ?? 'transparent';
    final base = resolveColorSettingValue(bgColorValue) ?? scheme.surface;
    final opacity =
        ((appdata.settings['backgroundImageOpacity'] as num?)?.toDouble() ??
                1.0)
            .clamp(0.0, 1.0);
    final fit = appdata.settings['backgroundImageFit'] as String? ?? 'cover';

    Widget layer = ColoredBox(color: base);

    final file = currentBackgroundImageFile();
    if (file != null) {
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
    return layer;
  }
}
