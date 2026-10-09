part of 'components.dart';

/// 全局自定义背景层：底色（可配置）+ 可选图片（透明度 / 显示方式）。
///
/// 由 `main.dart` 的 `MaterialApp.builder` 垫在所有内容之下。
/// 遮罩/圆角等通用 helper 见 `foundation/window_overlay.dart`。
/// ⭐ 修复（2026-10-09 用户 Android 实测 ✓）：**背景未就绪时的兜底色** ✓。
/// 与下面 `AppBackground.build` 的 `base` 同口径 ✓：背景底色（非透明）→ 否则主题表面色 ✓。
/// 用途 ✓：二级表面 / 弹窗底座等在**背景图解码完成前**露出的"底"，避免出现**白块** ✗
///（用户实测："有的地方白一块"✓；与 `background_slice.dart` 的首帧缓存配合，双保险 ✓）。
Color backgroundPlaceholderColor(ColorScheme scheme) {
  final v = appdata.settings['backgroundColor'] as String? ?? 'transparent';
  return resolveColorSettingValue(v) ?? scheme.surface;
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  /// 是否启用了自定义背景（有图片 或 底色非透明）。
  static bool get isActive => appdata.settings.backgroundFeatureActive;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：底色/背景图/透明度/显示方式变化时由框架精准重建本层
    // （取代 `App.forceRebuild()` 的整树遍历）。
    AppSettingsScope.of(context);
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

    // 图片路径/BoxFit 逻辑统一在 foundation/window_overlay.dart，
    // 避免此处与二级页面各写一份。
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
          fit: backgroundBoxFitOf(fit),
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
      layer = Stack(
        fit: StackFit.expand,
        children: [
          layer,
          Opacity(opacity: opacity, child: img),
        ],
      );
    }
    return layer;
  }
}
