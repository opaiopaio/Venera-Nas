part of 'components.dart';

/// ⭐ D1：**小标签（tag / chip）底色**的统一入口 ✓。
///
/// 由外观设置「标签颜色」（key `tagColorMode` ✓）控制：
/// - `overlay`（**默认** ✓）：`windowOverlayColor()` = 跟随**遮罩设置** ✓
///   （与分类页标签一致 ✓）；
/// - `theme`：`colorScheme.secondaryContainer` = 跟随**主题色** ✓（原样式 ✓）。
///
/// 选中态（`selected: true`）仍固定用 `secondaryContainer` ✓ —— 它表达"已选中"语义 ✓，
/// 与底色模式无关 ✓。
///
/// 用法：标签类控件统一走本函数 ✓（`MaskChip` ✓、卡片内 tag ✓ 等），
/// 这样"标签颜色"设置一处生效 ✓，不要在各处散写 `secondaryContainer` ✗。
Color tagFillColor(BuildContext context, {bool selected = false}) {
  // 建立设置依赖 ✓：改设置后标签即时刷新 ✓（见 11-refresh-mechanism.md）
  AppSettingsScope.of(context);
  final scheme = context.colorScheme;
  if (selected) return scheme.secondaryContainer;
  // ⭐ L1：标签底色**完全独立控制** ✓ —— 原「标签颜色」模式开关（`tagColorMode`：
  // 跟随遮罩 / 跟随主题 ✓）已按用户要求**删除** ✗；现在统一走 `tagOverlayColor()` ✓
  //（颜色默认跟随窗口 ✓、不透明度默认 0.85 ✓，可在「窗口与控件」区块单独设置 ✓）。
  // 想用主题色时：把「标签背景颜色」显式设为对应颜色即可 ✓。
  return tagOverlayColor();
}

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
    // 建立设置依赖：外观/设置变化时由框架**精准重建**本控件
    // （取代 App.forceRebuild() 的整树 markNeedsBuild 遍历，后者会导致鬼影）。
    AppSettingsScope.of(context);
    final scheme = context.colorScheme;
    final radius =
        windowOverlayBorderRadius() ?? BorderRadius.circular(AppRadius.md);
    final isSelected = selected ?? false;

    Widget chip = AnimatedContainer(
      duration: AppMotion.short,
      decoration: BoxDecoration(
        color: tagFillColor(context, selected: isSelected),
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
              // ⚠️ 不要用 Center/Align：它会**横向撑满可用宽度**，
              // 在 Wrap 里会让每个 chip 变成整行宽条（曾经的 bug）。
              // 高度由"内边距 + 文字行高"决定（minHeight 32 仅在必要时兜底）。
              child: Text(text, textAlign: TextAlign.center),
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
