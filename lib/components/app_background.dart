part of 'components.dart';

/// ⭐ 修复（2026-10-09 用户 Android 实测）：**背景未就绪时的兜底色**。
/// 与下面 `AppBackground.build` 的 `base` 同口径：背景底色（非透明）→ 否则主题表面色。
/// 用途：二级表面 / 弹窗底座等在背景图解码完成前露出的"底"，避免出现**白块**
/// （用户实测："有的地方白一块"；与 `background_slice.dart` 的首帧缓存配合，双保险）。
Color backgroundPlaceholderColor(ColorScheme scheme) {
  final v = appdata.settings['backgroundColor'] as String? ?? 'transparent';
  return resolveColorSettingValue(v) ?? scheme.surface;
}

/// 全局自定义背景层：底色（可配置）+ 可选图片（透明度 / 显示方式）。
///
/// 由 `main.dart` 的 `MaterialApp.builder` 垫在所有内容之下。
/// 遮罩/圆角等通用 helper 见 `foundation/window_overlay.dart`。
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

    Widget layer = ColoredBox(color: base);

    // 图片路径 / BoxFit 逻辑统一在 foundation/window_overlay.dart。
    // ⭐ 修复（2026-10-09 用户 Android 实测）：全局背景层的图改由 `BackgroundSlice` 绘制 ——
    // 原实现用 `Image.file`（走 Flutter 的 `ImageCache`），大壁纸在 Android 上会被挤出缓存，
    // 于是**切页时重新解码**，那几帧先露出底（未设背景色时即 `scheme.surface` 白）⇒ 观感"先白后出现"。
    // `BackgroundSlice` 自带**模块级解码缓存** ⇒ 首帧即有图；且它按**整窗**对齐绘制
    // （此处窗口偏移恒为 0），内部已处理 背景色 / 图片不透明度 / BoxFit / repeat
    // ⇒ 外层**不再叠** `Opacity`（叠两遍会让图变淡）。
    if (currentBackgroundImageFile() != null) {
      layer = Stack(
        fit: StackFit.expand,
        children: [layer, const BackgroundSlice()],
      );
    }
    return layer;
  }
}
