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
    required this.onPressed,
  });

  const Button.filled({
    super.key,
    required this.child,
    required this.onPressed,
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
    required this.onPressed,
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
    required this.onPressed,
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
    required this.onPressed,
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

  final void Function() onPressed;

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
    // P8 胶囊：默认内边距改为"水平 12 / 垂直 8"，避免又长又细 ✗（高度见下方 constraints ✓）
    var padding =
        widget.padding ??
        const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        );
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
        onTap: () {
          if (isLoading) return;
          widget.onPressed();
          if (widget.onPressedAt != null) {
            var renderBox = context.findRenderObject() as RenderBox;
            var offset = renderBox.localToGlobal(Offset.zero);
            widget.onPressedAt!(offset);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: padding,
          // P8 胶囊：抬到 44 高，避免细长 ✗（与主题注入的 `pillButtonStyle` 保持一致 ✓）
          constraints: const BoxConstraints(minWidth: 76, minHeight: 44),
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
    final mask = windowOverlayColor();
    if (widget.type == ButtonType.filled) {
      var color = widget.color ?? mask;
      return isHover ? color.toOpacity(0.9) : color;
    }
    if (widget.type == ButtonType.normal) {
      var color = widget.color ?? mask;
      return isHover ? color.toOpacity(0.9) : color;
    }
    // outlined / text：底色同样是遮罩色（未配置遮罩即透明 ✓），悬停时略加强 ✓
    if (widget.color != null) return widget.color!;
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
    if (widget.color != null) return context.colorScheme.onPrimary;
    if (widget.type == ButtonType.outlined || widget.type == ButtonType.text) {
      return global ?? context.colorScheme.primary;
    }
    return global ?? context.colorScheme.onSurface;
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
      icon: const Icon(Icons.more_horiz),
      onPressed: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        showMenuX(context, offset, widget.entries);
      },
    );
    return Tooltip(
      message: 'more'.tl,
      // 启用「窗口/按钮背景」时给「⋯」按钮一个圆角底色方块。
      child: appdata.settings.customBackgroundActive
          ? Material(
              color: windowOverlayColor(),
              borderRadius: windowOverlayBorderRadius(),
              clipBehavior: Clip.antiAlias,
              child: button,
            )
          : button,
    );
  }
}
