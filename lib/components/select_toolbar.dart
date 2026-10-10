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
/// ⭐ 例外（2026-10-10 用户实测反馈 ✓）：用户点名"四个按钮彼此太挤、按设计规范远一点" ✓
/// ⇒ 本轮**按用户要求**在动作之间补了令牌间距 ✓（见 `build` 内注释 ✓）；
/// 按钮自身的写法/尺寸/取色/禁用态/追加项行为未动 ✓。
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
    // ⭐ 本轮（用户实测反馈 ✓）：四个按钮原先**直接相邻、零间距** ✗
    // ⇒ 相邻按钮的 hover 底色几乎相贴 ✓，用户要求"按设计规范远一点" ✓。
    //
    // 做法 ✓：**只在动作之间**插一段令牌间距 ✓（`AppSpace.sm` ✓，与顶栏动作按钮
    // 的既有间距惯例同档 ✓；首尾不加 ⇒ 工具条两端的位置不变 ✓，零额外位移 ✓）。
    // ⚠️ 按钮本身的尺寸/图标/取色（继续走全局 `iconButtonTheme` ✓）以及
    // tooltip、`deleteEnabled` 禁用态、`extra` 追加项的行为**一律不变** ✓。
    final actions = <Widget>[
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
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.sm),
          actions[i],
        ],
      ],
    );
  }
}
