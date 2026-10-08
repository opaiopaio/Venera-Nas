part of 'components.dart';

class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;

  final BorderRadius borderRadius;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppMotion.short,
        decoration: BoxDecoration(
          color: isHover
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : null,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}

enum ButtonType { filled, outlined, text, normal }

/// P8 胶囊按钮的「图标 + 文字」内容（**统一**图标尺寸与间距 ✓）。
///
/// 用于把原先的 `TextButton.icon` / `FilledButton.icon` 等标准 M3 写法替换为
/// 应用自绘 `Button`（一套体系 ✓）：`Button.normal(child: pillLabel(Icons.x, "文本"))`。
Widget pillLabel(IconData icon, String text, {double size = AppIconSize.sm}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: size),
      const SizedBox(width: AppSpace.sm),
      Text(text),
    ],
  );
}

class Button extends StatefulWidget {
  const Button({
    super.key,
    required this.type,
    required this.child,
    this.isLoading = false,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.onPressed,
  });

  const Button.filled({
    super.key,
    required this.child,
    this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.filled;

  const Button.outlined({
    super.key,
    required this.child,
    this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.outlined;

  const Button.text({
    super.key,
    required this.child,
    this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.text;

  const Button.normal({
    super.key,
    required this.child,
    this.onPressed,
    this.width,
    this.height,
    this.padding,
    this.color,
    this.onPressedAt,
    this.isLoading = false,
  }) : type = ButtonType.normal;

  static Widget icon({
    Key? key,
    required Widget icon,
    required VoidCallback onPressed,
    double? size,
    Color? color,
    String? tooltip,
    bool isLoading = false,
    HitTestBehavior behavior = HitTestBehavior.deferToChild,
  }) {
    return _IconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      size: size,
      color: color,
      tooltip: tooltip,
      behavior: behavior,
      isLoading: isLoading,
    );
  }

  final ButtonType type;

  final Widget child;

  final bool isLoading;

  final void Function()? onPressed;

  final void Function(Offset location)? onPressedAt;

  final double? width;

  final double? height;

  final EdgeInsets? padding;

  final Color? color;

  @override
  State<Button> createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  bool isHover = false;

  bool isLoading = false;

  @override
  void didUpdateWidget(covariant Button oldWidget) {
    if (oldWidget.isLoading != widget.isLoading) {
      setState(() => isLoading = widget.isLoading);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    // P8 胶囊：水平内边距 **AppSpace.lg(16)** ✓（撤回此前的收窄 ✗）；**不要**加垂直内边距 ✗
    // （`height = widget.height - padding.vertical` 会吃掉调用方高度 → 文字被裁 ✗）。
    // 高度统一由 `constraints.minHeight: 40` 保证 ✓。
    var padding =
        widget.padding ?? const EdgeInsets.symmetric(horizontal: AppSpace.lg);
    var width = widget.width;
    if (width != null) {
      width = width - padding.horizontal;
    }
    var height = widget.height;
    if (height != null) {
      height = height - padding.vertical;
    }
    Widget child = IconTheme(
      data: IconThemeData(color: textColor),
      child: DefaultTextStyle(
        style: TextStyle(color: textColor, fontSize: 14),
        child: isLoading
            ? CircularProgressIndicator(
                color: widget.type == ButtonType.filled
                    ? context.colorScheme.inversePrimary
                    : context.colorScheme.primary,
                strokeWidth: 1.8,
              ).fixWidth(16).fixHeight(16)
            : widget.child,
      ),
    );
    if (width != null || height != null) {
      child = child.toCenter();
    }
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // ⭐ H2：自绘按钮支持**禁用态** ✓ —— `onPressed == null` 即禁用 ✓
        //（与 M3 的 `onPressed: null` 写法一致 ✓，95 处 M3 替换可**机械**进行 ✓）。
        onTap: widget.onPressed == null
            ? null
            : () {
                if (isLoading) return;
                widget.onPressed!();
                if (widget.onPressedAt != null) {
                  var renderBox = context.findRenderObject() as RenderBox;
                  var offset = renderBox.localToGlobal(Offset.zero);
                  widget.onPressedAt!(offset);
                }
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: padding,
          // P8 胶囊：高度**严格 32** ✓（min==max → 内容再大也撑不出去 ✓）。
          // ⭐ H2：**去掉 `minWidth: 64` 兜底** ✗ —— 用户明确的规范是
          // "宽度 = 文字宽度 + 两侧 `AppSpace.lg(16)` 延伸" ✓，短文案（如「OK」）
          // 不应被撑到 64 宽 ✗。
          constraints: const BoxConstraints(minHeight: 32, maxHeight: 32),
          // P8：胶囊形状 ✓；「窗口/按钮背景」设为直角时退化为直角 ✓（尊重用户形状设置）
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: windowOverlayBorderRadius() == null
                ? BorderRadius.zero
                : BorderRadius.circular(AppRadius.full),
            boxShadow:
                (isHover &&
                    !isLoading &&
                    (widget.type == ButtonType.filled ||
                        widget.type == ButtonType.normal))
                ? [
                    BoxShadow(
                      color: Colors.black.toOpacity(0.1),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
            border: widget.type == ButtonType.outlined
                ? Border.all(
                    color:
                        widget.color ??
                        Theme.of(context).colorScheme.outlineVariant,
                    width: 0.6,
                  )
                : null,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            child: SizedBox(
              width: width,
              height: height,
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }

  Color get buttonColor {
    // ─── P8 胶囊按钮规范（doc-private/03-implementation/07-background-and-color-picker.md）───
    // 底色 = **遮罩色**（`windowOverlayColor()` ✓，跟随「窗口/按钮背景颜色 × 不透明度」）。
    // 显式传 `widget.color` 时以显式色为准 ✓（危险操作如"删除"用 error 色的例外 ✓）。
    // ⭐ H2 禁用态：`onPressed == null` → 整体 **0.38 不透明度** ✓（P8 规范已写明 ✓）。
    final disabled = widget.onPressed == null;
    // ⭐ H3：按钮底色改用**独立入口** `buttonOverlayColor()` ✓ ——
    // 与「窗口背景」分离 ✓（原先与面板同色 ✗ → 叠在同色面板上完全融合 ✗）。
    // 颜色默认跟随**系统容器色** ✓；不透明度默认自动加强一档 ✓（默认不再融合 ✓）。
    // ⭐ I1 刷新修复：本 getter 在 `build` 期间求值 ✓ → 在此建立**设置依赖** ✓
    //（`AppSettingsScope.of(context)` ✓）。原先只读 `appdata.settings` ✗ 而无依赖 ✗ →
    // 改完「按钮背景颜色/不透明度」后，按钮**要点一下（hover 触发 setState）才同步** ✗
    //（用户实测反馈 ✓）。有了依赖，设置一变框架即精准重建本按钮 ✓（**不用** forceRebuild ✗）。
    AppSettingsScope.of(context);
    final mask = buttonOverlayColor();
    if (widget.type == ButtonType.filled) {
      var color = widget.color ?? mask;
      if (disabled) return color.toOpacity(0.38);
      return isHover ? color.toOpacity(0.9) : color;
    }
    if (widget.type == ButtonType.normal) {
      var color = widget.color ?? mask;
      if (disabled) return color.toOpacity(0.38);
      return isHover ? color.toOpacity(0.9) : color;
    }
    // outlined / text：底色同样是遮罩色（未配置遮罩即透明 ✓），悬停时略加强 ✓
    if (widget.color != null) {
      return disabled ? widget.color!.toOpacity(0.38) : widget.color!;
    }
    if (disabled) return mask.toOpacity(0.38);
    return isHover
        ? mask.toOpacity(mask.a >= 1 ? 1 : 0.5 + mask.a * 0.5)
        : mask;
  }

  Color get textColor {
    // ─── P8 胶囊按钮规范 ───
    // **文字统一跟随全局文字色** ✓（用户要求"按钮字体颜色也跟随设置" ✓）。
    // 由于 P8 底色已改为遮罩色（不再是强调色 ✗），全局文字色在其上可读 ✓。
    // 例外：显式传 `widget.color`（危险操作等）时用 `onPrimary` 保证对比度 ✓。
    // ⚠️ 图标（`IconTheme`）与 `iconButtonTheme` **不接**全局文字色 ✗（否则图标跟着变色）。
    final global = globalTextColor();
    // ⭐ H2 禁用态：文字与图标一并降到 **0.38 不透明度** ✓（P8 规范 ✓）
    final Color base;
    if (widget.color != null) {
      base = context.colorScheme.onPrimary;
    } else if (widget.type == ButtonType.outlined ||
        widget.type == ButtonType.text) {
      base = global ?? context.colorScheme.primary;
    } else {
      base = global ?? context.colorScheme.onSurface;
    }
    return widget.onPressed == null ? base.toOpacity(0.38) : base;
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size,
    this.color,
    this.tooltip,
    this.isLoading = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget icon;

  final VoidCallback onPressed;

  final double? size;

  final String? tooltip;

  final Color? color;

  final HitTestBehavior behavior;

  final bool isLoading;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool isHover = false;

  @override
  Widget build(BuildContext context) {
    var iconSize = widget.size ?? 24;
    Widget icon = IconTheme(
      data: IconThemeData(
        size: iconSize,
        color: widget.color ?? context.colorScheme.primary,
      ),
      child: widget.icon,
    );
    if (widget.isLoading) {
      icon = const CircularProgressIndicator(
        strokeWidth: 1.5,
      ).paddingAll(2).fixWidth(iconSize).fixHeight(iconSize);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => isHover = true),
      onExit: (_) => setState(() => isHover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: () {
          if (widget.isLoading) return;
          widget.onPressed();
        },
        child: Tooltip(
          message: widget.tooltip ?? "",
          child: Container(
            decoration: BoxDecoration(
              color: isHover
                  ? Theme.of(context).colorScheme.outlineVariant.toOpacity(0.4)
                  : null,
              borderRadius: BorderRadius.circular((iconSize + 12) / 2),
            ),
            padding: const EdgeInsets.all(AppSpace.tiny),
            child: icon,
          ),
        ),
      ),
    );
  }
}

class MenuButton extends StatefulWidget {
  const MenuButton({super.key, required this.entries});

  final List<MenuEntry> entries;

  @override
  State<MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<MenuButton> {
  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：本控件的外观由设置算出 → 设置变化时由框架精准重建
    // （见 doc-private/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    final button = Button.icon(
      // ⭐ C1：`MenuButton` 的「⋯」图标走统一取色 ✓ ——
      // `Button.icon` 会把自身文字色套给图标 ✗（内部 `IconThemeData(color: textColor)` ✓，
      // 见本文件 192/345 行 ✓），所以这里显式给 `Icon` 上色 ✓（`Icon` 自身的 `color`
      // 优先级**高于** `IconTheme` ✓）。未设置全局图标色时传 `null` ✓ →
      // 回落为原来的"按钮文字色" ✓（观感不变 ✓，用户实测：侧栏与页面右上「⋯」
      // 一直不跟随图标颜色 ✗，即此处 ✓）。
      icon: Icon(Icons.more_horiz, color: appIconColor(context)),
      onPressed: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        showMenuX(context, offset, widget.entries);
      },
    );
    return Tooltip(
      message: 'more'.tl,
      // 启用「窗口/按钮背景」时给「⋯」按钮一个圆角底色方块。
      // ⭐ I1：底色走**按钮独立入口** ✓（原先 `windowOverlayColor()` ✗ → 与面板同色、不受「按钮背景」控制 ✗）
      child: appdata.settings.customBackgroundActive
          ? Material(
              color: iconOverlayColor(),
              borderRadius: windowOverlayBorderRadius(),
              clipBehavior: Clip.antiAlias,
              child: button,
            )
          : button,
    );
  }
}
