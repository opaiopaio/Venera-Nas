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
    return Button.outlined(
      // ⭐ 外观构件统一 · 第三批（2026-10-10 ✓）：原先**自绘**描边锚点（`Container + Border.all + InkWell`）✗
      // ⇒ 现走规范构件 `Button.outlined` ✓，按**现状逐项传参** ⇒ 观感逐字不变 ✓：
      // 无底色（`fillColor` 透明 ✓）/ 圆角 AppRadius.sm ✓ / **描边宽 1.0**（用新增的 `borderWidth` ✓ ——
      // `outlined` 默认 0.6 ✗，不传会变细 ⇒ 必须显式传 ✓）/ 描边色沿用默认 outlineVariant ✓ /
      // 内边距 h md · v xs ✓ / 高度由内容决定 ✓（传无界约束 ✓）。
      // ⚠️ 下方 `showMenu` 的**锚点坐标计算原样保留** ✓ —— 那两处修复（紧贴菜单 + 取根 overlay ✓）很宝贵 ✓，一行未动 ✓。
      fillColor: Colors.transparent,
      textColor: DefaultTextStyle.of(context).style.color,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderWidth: 1,
      constraints: const BoxConstraints(
        minHeight: 0,
        maxHeight: double.infinity,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs,
      ),
      onPressed: () {
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
        // ⭐ 复查修复（2026-10-09 ✓，本轮专项复查发现 ✗）：**必须取"根 overlay"** ✗→✓ ——
        // 下面 `showMenu` 传的是 `useRootNavigator: true` ✓（菜单落在**根** navigator 的 overlay ✓），
        // 而这里原先写 `Overlay.of(context)` ✗ = **最近**的 overlay ✓ —— 本项目里最近 overlay
        // **一定不是**根 overlay ✓（`components/navigation_bar.dart` 把主 Navigator 放在
        // `Positioned.fill(left: 72/224)` 内 ✓，设置右栏还有一层内层 Navigator ✓）→
        // 锚点坐标基于"内层 overlay 原点" ✗ 而菜单按"根 overlay 原点"布局 ✓ → **位置会偏** ✗
        //（分类筛选、搜索页等左对齐的 Select 最明显 ✓）。
        // 旧代码用的是不带 `ancestor` 的 `localToGlobal(Offset.zero)` ✓（= 窗口/根坐标 ✓）→
        // 与我上一轮改成"只算差值"的做法**坐标系必须同源** ✓，故这里改为 `rootOverlay: true` ✓。
        final overlayBox =
            Overlay.of(context, rootOverlay: true).context.findRenderObject()
                as RenderBox;
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
                  // 记为该约定的**例外** ✓ —— 见 ../workspace/archive/doc-private-legacy-20261009/16-audit-fix-plan.md ✓。
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
      child: Row(
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
      ),
    );
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
