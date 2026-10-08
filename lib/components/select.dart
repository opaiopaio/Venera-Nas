part of 'components.dart';

class Select extends StatelessWidget {
  const Select({
    super.key,
    required this.current,
    required this.values,
    this.onTap,
    this.minWidth,
  });

  final String? current;

  final List<String> values;

  final void Function(int index)? onTap;

  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: InkWell(
        onTap: () {
          var renderBox = context.findRenderObject() as RenderBox;
          var size = renderBox.size;
          // ⭐ 修复（2026-10-09 用户反馈 ✓）：菜单必须与按钮**紧贴** ✗→✓ ——
          // 原先用 `RelativeRect.fromLTRB(offset.dx, offset.dy + size.height + 2,
          // offset.dx + size.height + 2, offset.dy)` ✗：该构造的第 3、4 个参数是
          // **right / bottom**（= 距 overlay **右缘 / 下缘**的距离 ✓），却被塞进了
          // `left + 高度` 与 `top` ✗（把 left/top 当 right/bottom 用 ✗）→ 位置被算歪 ✓，
          // 表现为"**下拉菜单与按钮差一个选项的距离**"✗（用户截图实测 ✓）。
          // 现改用 Flutter `showMenu` 官方文档的标准算法 ✓：以**锚点矩形**表达位置 ✓
          //（`ancestor` 取 overlay ✓，保证 `useRootNavigator: true` 下坐标系一致 ✓）。
          final overlayBox =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          final anchorTopLeft = renderBox.localToGlobal(
            Offset.zero,
            ancestor: overlayBox,
          );
          final anchorBottomRight = renderBox.localToGlobal(
            renderBox.size.bottomRight(Offset.zero),
            ancestor: overlayBox,
          );
          showMenu(
            elevation: 3,
            // ⭐ C6-新③（2026-10-09 审计 ✓）：原为**写死**的亮/暗两色 ✗
            //（`0xFFF6F6F6` / `0xFF1E1E1E` ✓）—— 完全脱离主题 ✓：改主题色/换亮暗、或启用
            // 「窗口与控件」体系后，这个下拉菜单都**不跟着变** ✗。现改走**主题表面色** ✓
            //（`colorScheme.surface` ✓，M3 下亮暗分别接近原来那两个值 ✓ → 观感变化很小 ✓）。
            color: context.colorScheme.surface,
            context: context,
            useRootNavigator: true,
            constraints: BoxConstraints(
              minWidth: size.width,
              maxWidth: size.width,
            ),
            // ⭐ 修复（2026-10-09 用户反馈 ✓）：改用**锚点矩形**（见上方注释 ✓）。
            position: RelativeRect.fromRect(
              Rect.fromPoints(anchorTopLeft, anchorBottomRight),
              Offset.zero & overlayBox.size,
            ),
            items: values
                .map(
                  (e) => PopupMenuItem(
                    // ⭐ C6-新③（2026-10-09 实测纠正 ✓）：本条**不能**用 `minHeight` ✗ ——
                    // `PopupMenuItem` **只提供固定 `height`** ✓，传入 `minHeight` 会编译失败 ✗
                    //（我已实测：`The named parameter 'minHeight' isn't defined` ✓）。
                    // 因此这里保留原有固定高度 ✓（46/40 ✓），并**不改数值** ✓ 以免观感突变 ✗；
                    // 记为该约定的**例外** ✓ —— 见 doc-private/16-audit-fix-plan.md ✓。
                    height: App.isMobile ? 46 : 40,
                    value: e,
                    child: Text(e),
                  ),
                )
                .toList(),
          ).then((value) {
            if (value != null) {
              onTap?.call(values.indexOf(value));
            }
          });
        },
        child:
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: minWidth != null ? (minWidth! - 32) : 0,
                  ),
                  child: Text(current ?? ' ', style: ts.s14),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_drop_down,
                  // A8：走统一图标取色 ✓（全局图标色优先；未设置回退主题色 ✓）
                  color: appIconColor(context, context.colorScheme.primary),
                ),
              ],
            ).padding(
              const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.xs,
              ),
            ),
      ),
    );
  }
}

class FilterChipFixedWidth extends StatefulWidget {
  const FilterChipFixedWidth({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Widget label;

  final bool selected;

  final void Function(bool) onSelected;

  @override
  State<FilterChipFixedWidth> createState() => _FilterChipFixedWidthState();
}

class _FilterChipFixedWidthState extends State<FilterChipFixedWidth> {
  get selected => widget.selected;

  double? labelWidth;

  double? labelHeight;

  var key = GlobalKey();

  @override
  void initState() {
    Future.microtask(measureSize);
    super.initState();
  }

  void measureSize() {
    final RenderBox renderBox =
        key.currentContext!.findRenderObject() as RenderBox;
    labelWidth = renderBox.size.width;
    labelHeight = renderBox.size.height;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: appdata.settings.customBackgroundActive
          ? windowOverlayColor()
          : null,
      textStyle: Theme.of(context).textTheme.labelLarge,
      child: InkWell(
        onTap: () => widget.onSelected(true),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        child: AnimatedContainer(
          duration: _fastAnimationDuration,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.md,
            AppSpace.sm,
          ),
          child: labelWidth == null ? firstBuild() : buildContent(),
        ),
      ),
    );
  }

  Widget firstBuild() {
    return Center(
      child: SizedBox(key: key, child: widget.label),
    );
  }

  Widget buildContent() {
    const iconSize = 18.0;
    const gap = 4.0;
    return SizedBox(
      width: iconSize + labelWidth! + gap,
      height: math.max(iconSize, labelHeight!),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: _fastAnimationDuration,
            left: selected ? (iconSize + gap) : (iconSize + gap) / 2,
            child: widget.label,
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: labelWidth! + gap,
              child: const AnimatedCheckIcon(size: iconSize).toCenter(),
            ),
        ],
      ),
    );
  }
}

class AnimatedCheckWidget extends AnimatedWidget {
  const AnimatedCheckWidget({
    super.key,
    required Animation<double> animation,
    this.size,
  }) : super(listenable: animation);

  final double? size;

  @override
  Widget build(BuildContext context) {
    var iconSize = size ?? IconTheme.of(context).size ?? 25;
    final animation = listenable as Animation<double>;
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: animation.value,
          child: ClipRRect(
            child: Icon(
              Icons.check,
              size: iconSize,
              color: appIconColor(
                context,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedCheckIcon extends StatefulWidget {
  const AnimatedCheckIcon({this.size, super.key});

  final double? size;

  @override
  State<AnimatedCheckIcon> createState() => _AnimatedCheckIconState();
}

class _AnimatedCheckIconState extends State<AnimatedCheckIcon>
    with SingleTickerProviderStateMixin {
  late Animation<double> animation;
  late AnimationController controller;

  @override
  void initState() {
    controller = AnimationController(
      vsync: this,
      duration: _fastAnimationDuration,
    );
    animation = Tween<double>(begin: 0, end: 1).animate(controller)
      ..addListener(() {
        setState(() {});
      });
    controller.forward();
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedCheckWidget(animation: animation, size: widget.size);
  }
}

class OptionChip extends StatelessWidget {
  const OptionChip({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final String text;

  final bool isSelected;

  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    // 同类 chip 统一规格（内边距/最小高度/圆角/文字居中/选中态）见 mask_chip.dart。
    return MaskChip(text: text, selected: isSelected, onTap: onTap);
  }
}
