part of 'components.dart';

/// ⭐ D1：**小标签（tag / chip）底色**的统一入口 ✓。
///
/// ⚠️ **复查修正** ✗：本文档原写"由外观设置「标签颜色」（key `tagColorMode`）控制"——
/// 该开关**已按用户要求删除** ✗（见下方 L1 注释 ✓），措辞已过期 ✓。
/// **现值** ✓：统一走 `tagOverlayColor()` ✓ ——
/// - **颜色**：默认跟随**系统容器色** ✓，可在「窗口与控件 → 标签背景颜色」单独设置 ✓；
/// - **不透明度**：默认 0.85 ✓，同区块可调 ✓；
/// - 想要**主题色**：把「标签背景颜色」显式设成对应颜色即可 ✓（不再有模式开关 ✓）。
///
/// 选中态（`selected: true`）固定用 `primaryContainer` ✓ —— 它表达"已选中"语义 ✓，
/// 与底色模式无关 ✓。
///
/// ⭐ 2026-10-10（用户实测反馈 ✓）：**选中态原先用 `secondaryContainer` 太不显眼** ✗ ——
/// 「外观全部跟随主题」时它与未选中的 `tagOverlayColor()`（系统容器色 × 0.85）几乎同色 ✓，
/// 而选中态又把描边设成**与填充同色** ✗ ⇒ 唯一差别只剩"未选中才有描边" ⇒ **看不出谁被选中** ✓。
/// 现改为 `primaryContainer` ✓（更强色调 ✓，配 `MaskChip` 的 `onPrimaryContainer` 文字 ✓ =
/// Material 成对色 ⇒ 对比度有保证 ✓、且天然跟随主题/自定义配色 ✓）。
Color tagFillColor(BuildContext context, {bool selected = false}) {
  // 建立设置依赖 ✓：改设置后标签即时刷新 ✓（见 11-refresh-mechanism.md）
  AppSettingsScope.of(context);
  final scheme = context.colorScheme;
  if (selected) return scheme.primaryContainer;
  // ⭐ L1：标签底色**完全独立控制** ✓ —— 原「标签颜色」模式开关（`tagColorMode`：
  // 跟随遮罩 / 跟随主题 ✓）已按用户要求**删除** ✗；现在统一走 `tagOverlayColor()` ✓
  //（颜色默认跟随**系统容器色** ✓、不透明度默认 0.85 ✓，可在「窗口与控件」区块单独设置 ✓）。
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
/// - **选中填充：`primaryContainer` ＋ 文字 `onPrimaryContainer` ＋ 描边 `primary`**
///   （⭐ 2026-10-10 用户要求 ✓：**靠颜色变化突出选中** 而非只靠描边 ✓ —— 旧实现填充 `secondaryContainer`
///   且描边与填充**同色** ✗ ⇒ 跟随主题时选中/未选中几乎一样 ⇒ 用户"根本看不出按钮被选中" ✓）
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
    // ⭐ 对比度（2026-10-11）：**未选中态**的填充是自绘的遮罩色 ✓（可被设成浅色 ✗）⇒
    // 文字必须取与填充成对的前景色 ✓；**选中态保持原样** ✗（填充 `primaryContainer` 配
    // `onPrimaryContainer` 已是成对色 ✓，见下）。
    final unselectedFill = isSelected
        ? null
        : tagFillColor(context, selected: false);
    // ⭐ 2026-10-10（用户要求 ✓）：**选中 = 颜色变化** ✓ ——
    // 填充 `primaryContainer` ✓、文字 `onPrimaryContainer` ✓、描边 `primary` ✓（三者成对 ✓ 对比度有保证 ✓）；
    // 未选中保持原样 ✓（填充 `tagOverlayColor()`、描边 `outline` ✓、文字沿用主题 ✓）。
    // ⚠️ 只改 `MaskChip`（= `OptionChip` ✓）这一族 ✓；**顶栏「漫画源」标签不走这里** ✓
    //（`home_page.dart` 的 `_ComicSourceWidget` 直接调 `tagFillColor(context)` 不带 selected ✓ ⇒ 不受影响 ✓）。
    final selectedFill = isSelected ? scheme.primaryContainer : null;
    final selectedOnColor = isSelected ? scheme.onPrimaryContainer : null;

    Widget chip = AnimatedContainer(
      duration: AppMotion.short,
      decoration: BoxDecoration(
        color: selectedFill ?? tagFillColor(context, selected: false),
        borderRadius: radius,
        border: selected == null
            ? null
            : Border.all(color: isSelected ? scheme.primary : scheme.outline),
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
              // ⚠️ 选中态必须显式给对比文字色 ✗（否则会"深底深字" ✗）；`Text.style` 会与
              // 环境 `DefaultTextStyle` **合并** ✓ ⇒ 字号/字重等仍沿用主题 ✓ 不丢 ✓。
              // ⭐ 对比度（2026-10-11）：**未选中态**填充也是自绘的遮罩色 ✓（可被设成浅色 ✗）⇒
              // 紧贴文字包一层前景注入 ✓（放在 `Material`/`InkWell` 内部 ⇒ 不影响选中态 ✗）。
              child: FilledForeground(
                fill: unselectedFill,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: selectedOnColor == null
                      ? null
                      : TextStyle(color: selectedOnColor),
                ),
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
