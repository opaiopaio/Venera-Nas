part of 'components.dart';

/// 「选择 / 标签 chip」类的**唯一实现**。
///
/// 同类使用者：分类页的主题与排行榜标签（[categories_page] 的 `buildTag`）、
/// 选项 chip（`select.dart` 的 `OptionChip`）。
///
/// **统一规格**（改这里即同时改所有同类）：
/// - 内边距：`horizontal AppSpace.lg(16)` / `vertical AppSpace.sm(8)`
/// - 最小高度：32（`minHeight`，字号放大时自适应撑开，不用固定 height）
/// - 圆角：`windowOverlayBorderRadius() ?? AppRadius.md` → **跟随「圆角/直角」设置**
/// - 文字：居中
/// - 未选中填充：`windowOverlayColor()`（跟随遮罩色 × 不透明度）
/// - 选中填充：`colorScheme.secondaryContainer`（+ 同色描边）
/// - 外间距（Wrap 场景）：`horizontal AppSpace.sm(8)` / `vertical AppSpace.tiny(6)`
///
/// ⚠️ **不要**用它同化顶栏「漫画源」标签：那一类属于更宽松的卡片式标签，
/// 规格不同（有意为之），见 `home_page.dart` 的 `_ComicSourceWidget`。
class MaskChip extends StatelessWidget {
  const MaskChip({
    super.key,
    required this.text,
    this.onTap,
    this.selected,
    this.withMargin = false,
  });

  final String text;

  final VoidCallback? onTap;

  /// `null` = 该类标签**没有选中概念**（如分类页主题标签，不加描边）。
  final bool? selected;

  /// Wrap 场景下由 chip 自带外间距（保证同类间距一致）。
  final bool withMargin;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final radius =
        windowOverlayBorderRadius() ?? BorderRadius.circular(AppRadius.md);
    final isSelected = selected ?? false;

    Widget chip = AnimatedContainer(
      duration: AppMotion.short,
      decoration: BoxDecoration(
        color: isSelected ? scheme.secondaryContainer : windowOverlayColor(),
        borderRadius: radius,
        border: selected == null
            ? null
            : Border.all(
                color: isSelected ? scheme.secondaryContainer : scheme.outline,
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              child: Center(
                child: Text(text, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );

    if (withMargin) {
      chip = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.tiny,
        ),
        child: chip,
      );
    }
    return chip;
  }
}
