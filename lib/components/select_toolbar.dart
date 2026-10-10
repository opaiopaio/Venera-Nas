part of 'components.dart';

/// ⭐ 外观构件统一 · 第二批（2026-10-10 ✓）：**多选工具条的唯一实现** ✓
///
/// **背景** ✗：原先在 6 个页面**逐行重复**同一组按钮 ——
/// `home_page` / `history_page` / `local_comics_page` / `comic_page` /
/// `image_favorites_page` / `image_favorites_gallery_page` ✓，
/// 同一外观要改六遍 ⇒ 正是"同类构件多套实现"的典型 ✓。
///
/// **原则** ✓：**只统一实现、不改变外观** ✓ —— 本组件内部仍使用与原先**逐字相同**的
/// `IconButton(icon:, tooltip:, onPressed:)` 写法 ✓（继续走全局 `iconButtonTheme` ✓ 的取色与尺寸 ✓），
/// 因此迁移后观感与原先**完全一致** ✓。
///
/// **用法** ✓：只传本页需要的动作 ✓（null ⇒ 不渲染该按钮 ✓），例如只需要全选/取消/反选就只传前三个 ✓。
class SelectToolbar extends StatelessWidget {
  const SelectToolbar({
    super.key,
    this.onSelectAll,
    this.onDeSelect,
    this.onInvert,
    this.onDelete,
    this.deleteEnabled = true,
    this.deleteIcon = Icons.delete,
    this.extra = const <Widget>[],
  });

  /// 「全选」✓（null ⇒ 不显示 ✓）。
  final VoidCallback? onSelectAll;

  /// 「取消选择」✓（null ⇒ 不显示 ✓）。
  final VoidCallback? onDeSelect;

  /// 「反选」✓（null ⇒ 不显示 ✓）。
  final VoidCallback? onInvert;

  /// 「删除」✓（null ⇒ 不显示 ✓）。
  final VoidCallback? onDelete;

  /// 删除按钮是否可点 ✓ —— 与原先 `onPressed: selected.isEmpty ? null : …` **等价** ✓
  ///（false ⇒ 走 `IconButton` 的 `onPressed: null` 禁用态 ✓）。
  final bool deleteEnabled;

  /// 删除按钮的图标 ✓（个别页面用 `Icons.delete_outline` ✓，默认 `Icons.delete` ✓）。
  final IconData deleteIcon;

  /// 追加在末尾的自定义动作 ✓（如某页原有的额外菜单/按钮 ✓）。
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onSelectAll != null)
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: "Select All".tl,
            onPressed: onSelectAll,
          ),
        if (onDeSelect != null)
          IconButton(
            icon: const Icon(Icons.deselect),
            tooltip: "Deselect".tl,
            onPressed: onDeSelect,
          ),
        if (onInvert != null)
          IconButton(
            icon: const Icon(Icons.flip),
            tooltip: "Invert Selection".tl,
            onPressed: onInvert,
          ),
        if (onDelete != null)
          IconButton(
            icon: Icon(deleteIcon),
            tooltip: "Delete".tl,
            onPressed: deleteEnabled ? onDelete : null,
          ),
        ...extra,
      ],
    );
  }
}
