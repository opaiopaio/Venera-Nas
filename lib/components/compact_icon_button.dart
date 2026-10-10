part of 'components.dart';

/// ⭐ 外观构件统一 · 第四批（2026-10-10 ✓）：**紧凑图标按钮的唯一实现** ✓
///
/// **背景** ✗：`IconButton` 默认 **48×48** ✗，塞进定高行里会把行撑高 ⇒
/// `ListTile` 内容贴底、不在遮罩内垂直居中 ✗（用户实测 ✓）。
/// 于是**两处各写了一遍**同一个"魔法组合" ✗（`padding: EdgeInsets.zero` +
/// `constraints: BoxConstraints(minWidth: 32, minHeight: 32)` ✓）——
/// `pages/settings/setting_components.dart` 与
/// `pages/image_favorites_page/image_favorites_item.dart` ✓，
/// 且后者的注释还写着"与图片收藏的网格按钮同法"✓ —— 典型的"同类构件多套实现" ✓。
///
/// **原则** ✓：**只统一实现、不改变外观** ✓ —— 内部仍使用与原先**逐字相同**的
/// 原始 `IconButton` 写法 ✓（继续走全局 `iconButtonTheme` ✓ 的取色与圆角 ✓），
/// 因此迁移后观感与原先**完全一致** ✓。
///
/// **注意** ✓：本组件**不是** `Button.icon` ✗ —— 二者取色入口不同 ✓
///（`Button.icon` 走 `colorScheme.primary` + hover 底色 ✓；本组件走全局 `iconButtonTheme`
/// ⇒ `iconOverlayColor()` ✓）。**同类控件只统一同类** ✓，不可互相替换 ✗。
class CompactIconButton extends StatelessWidget {
  const CompactIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final Widget icon;

  final VoidCallback? onPressed;

  /// 与原 `IconButton(tooltip: …)` 等价 ✓（null ⇒ 不显示提示 ✓）。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      // 紧凑化 ✓：与原先两处**逐字一致** ✓ —— `IconButton` 默认 48×48 ✗ 会把定高行撑高 ⇒ 内容贴底 ✗。
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
