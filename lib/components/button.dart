part of 'components.dart';

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
    this.onLongPress,
    this.onSecondaryTapAt,
    this.constraints,
    this.borderRadius,
    this.hoverColor,
    this.disabledColor,
    this.fillColor,
    this.borderWidth = 0.6,
    this.textColor,
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
    this.onLongPress,
    this.onSecondaryTapAt,
    this.constraints,
    this.borderRadius,
    this.hoverColor,
    this.disabledColor,
    this.fillColor,
    this.borderWidth = 0.6,
    this.textColor,
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
    this.onLongPress,
    this.onSecondaryTapAt,
    this.constraints,
    this.borderRadius,
    this.hoverColor,
    this.disabledColor,
    this.fillColor,
    this.borderWidth = 0.6,
    this.textColor,
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
    this.onLongPress,
    this.onSecondaryTapAt,
    this.constraints,
    this.borderRadius,
    this.hoverColor,
    this.disabledColor,
    this.fillColor,
    this.borderWidth = 0.6,
    this.textColor,
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
    this.onLongPress,
    this.onSecondaryTapAt,
    this.constraints,
    this.borderRadius,
    this.hoverColor,
    this.disabledColor,
    this.fillColor,
    this.borderWidth = 0.6,
    this.textColor,
    this.isLoading = false,
  }) : type = ButtonType.normal;

  static Widget icon({
    Key? key,
    required Widget icon,
    VoidCallback? onPressed,
    IconButtonBackground background = IconButtonBackground.hover,
    Color? backgroundColor,
    bool active = false,
    Color? activeColor,
    bool dense = false,
    EdgeInsets? padding,
    bool danger = false,
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
      background: background,
      backgroundColor: backgroundColor,
      active: active,
      activeColor: activeColor,
      dense: dense,
      padding: padding,
      danger: danger,
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

  final void Function()? onLongPress;
  final void Function(Offset location)? onSecondaryTapAt;
  final BoxConstraints? constraints;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? disabledColor;

  /// ⭐ 第 0 步补充 ✓：**显式指定填充色**（`Colors.transparent` 即"只有描边、不填充" ✓），
  /// 用于复现"手搓描边胶囊"等**原本没有底色**的控件 ✓；不影响描边色（描边仍看 `color` ✓）。
  final Color? fillColor;

  /// ⭐ 第三批补充（2026-10-10 ✓）：**描边宽度**可由调用方覆盖 ✓，默认 **0.6** = 改造前**逐字一致** ✓。
  /// 引入原因 ✓：`components/select.dart` 的 `Select` 锚点原为 `Border.all(color: …)` = 宽度 **1.0** ✗，
  /// 要把它收编进 `Button.outlined` 且**观感不变** ✓ ⇒ 必须先能表达这个值 ✓（**仅 `ButtonType.outlined` 生效** ✓）。
  final double borderWidth;

  /// ⭐ 第 0 步补充 ✓：**显式指定文字/图标颜色**（null ⇒ 沿用原有分支 ✓），
  /// 用于复现"用继承默认文字色"的手搓件 ✓（迁移时传 `DefaultTextStyle.of(context).style.color` ⇒ 逐字复现 ✓）。
  final Color? textColor;

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
      child: Material(
        // ⭐ 水波统一（2026-10-10 用户实测 ✓）：**Material 必须放在底色之上** ✗→✓
        // 上一版把 Material/InkWell 包在 AnimatedContainer **外层** ✗ ⇒ 墨水被容器的不透明底色**盖住**
        // ⇒ 点击完全看不到水波 ✗（用户怀疑"被覆盖" ✓ —— 实测确认 ✓）。
        // 现放进**容器内层** ✓ ⇒ 墨水绘制在底色之上、内容之下 ✓（Flutter 语义：墨水由最近的 Material 绘制 ✓）。
        // 同时把**真正的回调**从 GestureDetector 移到 InkWell ✓ —— 同一个手势识别器负责水波与功能 ✓，
        // 不再出现"内层抢走手势、外层收不到点击"的事故 ✗（2026-10-10 曾因此让全仓按钮点不动 ✓）。
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius:
              widget.borderRadius ??
              (windowOverlayBorderRadius() == null
                  ? BorderRadius.zero
                  : BorderRadius.circular(AppRadius.full)),
          // 水波/按压反馈用**令牌透明度** ✓（不写字面量 ✗，守卫棘轮"只许降不许升" ✓）。
          splashColor: Theme.of(
            context,
          ).colorScheme.onSurface.toOpacity(AppOpacity.tintStrengthDefault),
          highlightColor: Theme.of(
            context,
          ).colorScheme.onSurface.toOpacity(AppOpacity.hoverInk),
          // ⭐ 第 0 步 ✓：补长按与右键能力 ✓（不传 ⇒ null ⇒ 行为与原先**逐字一致** ✓）
          onLongPress: widget.onLongPress,
          onSecondaryTapUp: widget.onSecondaryTapAt == null
              ? null
              : (details) => widget.onSecondaryTapAt!(details.globalPosition),
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
            // P8 胶囊：高度**严格 32** ✓（min==max → 内容再大也撑不出去 ✓）。
            // ⭐ H2：**去掉 `minWidth: 64` 兜底** ✗ —— 用户明确的规范是
            // "宽度 = 文字宽度 + 两侧 `AppSpace.lg(16)` 延伸" ✓，短文案（如「OK」）
            // 不应被撑到 64 宽 ✗。
            // ⭐ 第 0 步（2026-10-10 ✓）：高度约束可由调用方覆盖 ✓（不传 ⇒ 与原先**逐字一致**的 32 ✓）
            // ⭐ 本轮（用户拍板 ✓）：**显式 `height` 必须真的生效** ✗→✓ ——
            // 原先恒定 `minHeight: 32` 与 `maxHeight: 32` ✗ ⇒ 即使 `height` 换算出的内容盒更高，
            // 也会被上限剪回 32 ✗（该参数此前**形同虚设** ✓：实测传 40 仍渲染成 32 ✗）。
            // `height` 的既有语义 = **含内边距的总高** ✓（见上方 `height - padding.vertical` ✓）⇒
            // 显式传 `height` 时改用**不设上下限**的约束 ✓，让内层 `SizedBox(height:)` 说了算 ✓。
            // ⚠️ 默认（既不传 `height` 也不传 `constraints`）仍**严格 32** ✓ —— 全仓 161 个 `Button`
            // 调用点中**无人传 `height`** ✓（扫描实测 ✓）⇒ 观感零变化 ✓。
            constraints:
                widget.constraints ??
                (widget.height != null
                    ? const BoxConstraints()
                    : const BoxConstraints(minHeight: 32, maxHeight: 32)),
            // P8：胶囊形状 ✓；「窗口/按钮背景」设为直角时退化为直角 ✓（尊重用户形状设置）
            decoration: BoxDecoration(
              color: buttonColor,
              // ⭐ 第 0 步 ✓：圆角可由调用方覆盖 ✓（不传 ⇒ 沿用"全圆/直角"现有逻辑 ✓）
              borderRadius:
                  widget.borderRadius ??
                  (windowOverlayBorderRadius() == null
                      ? BorderRadius.zero
                      : BorderRadius.circular(AppRadius.full)),
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
                      width: widget.borderWidth,
                    )
                  : null,
            ),
            child: Padding(
              padding: padding,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 160),
                child: SizedBox(
                  width: width,
                  height: height,
                  // ⭐ 本轮（用户实测反馈 ✓）：内容盒的**高度必须由内容决定** ✗→✓ ——
                  // 加 `heightFactor: 1` ⇒ 高度收缩到内容高度 ✓；原先为 `null` ✗ ⇒
                  // 只要父级给了**有界**高度（例如 `ListTile.trailing` 那一格 ✓），
                  // `Center` 就会**撑满父级高度** ✗ ⇒ `Select` 的描边框会贴住遮罩上下边 ✗。
                  // 影响面 ✓：调用方传的约束若把高度**钉死**（默认按钮就是 32 ✓、显式 `height:` ✓），
                  // 结果仍被约束钉在同一值 ⇒ **零影响** ✓；只有"高度由内容决定"那类调用方
                  //（`Select` ✓、`CommentActionChip` ✓ 都传了无界 `maxHeight` ✓）
                  // 才**恢复到它们重构前**的内容高度 ✓。
                  child: Center(widthFactor: 1, heightFactor: 1, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get buttonColor {
    // ─── P8 胶囊按钮规范（../workspace/archive/doc-private-legacy-20261009/03-implementation/07-background-and-color-picker.md）───
    // 底色 = **遮罩色**（`windowOverlayColor()` ✓，跟随「窗口/按钮背景颜色 × 不透明度」）。
    // 显式传 `widget.color` 时以显式色为准 ✓（危险操作如"删除"用 error 色的例外 ✓）。
    // ⭐ H2 禁用态：`onPressed == null` → 整体 **0.38 不透明度** ✓（P8 规范已写明 ✓）。
    final disabled = widget.onPressed == null;
    // ⭐ 第 0 步补充 ✓：**fillColor 优先**（显式填充，含 `Colors.transparent` = 不填充 ✓）
    // ⇒ 复现"无底色"控件时，hover 也不会突然出现底色 ✓（透明叠加仍透明 ✓）。
    if (widget.fillColor != null) {
      final fill = widget.fillColor!;
      if (disabled) return fill.toOpacity(AppOpacity.disabled);
      // ⭐ 说明 ✓：`fillColor` 分支**不做 hover 变化** ✓ —— 其一为"透明填充"（hover 变透明无意义 ✓），
      // 其二避免新增裸透明度字面量 ✓（守卫棘轮"只许降不许升" ✗）。
      return fill;
    }
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
      if (disabled) {
        return widget.disabledColor ?? color.toOpacity(AppOpacity.disabled);
      }
      return isHover ? (widget.hoverColor ?? color.toOpacity(0.9)) : color;
    }
    if (widget.type == ButtonType.normal) {
      var color = widget.color ?? mask;
      if (disabled) {
        return widget.disabledColor ?? color.toOpacity(AppOpacity.disabled);
      }
      return isHover ? (widget.hoverColor ?? color.toOpacity(0.9)) : color;
    }
    // outlined / text：底色同样是遮罩色（未配置遮罩即透明 ✓），悬停时略加强 ✓
    if (widget.color != null) {
      return disabled
          ? widget.color!.toOpacity(AppOpacity.disabled)
          : widget.color!;
    }
    if (disabled) return mask.toOpacity(AppOpacity.disabled);
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
    // ⭐ 第 0 步补充 ✓：显式 textColor 优先 ✓（null ⇒ 沿用下面原有分支 ✓）
    if (widget.textColor != null) {
      return widget.onPressed == null
          ? widget.textColor!.toOpacity(AppOpacity.disabled)
          : widget.textColor!;
    }
    final Color base;
    if (widget.color != null) {
      base = context.colorScheme.onPrimary;
    } else if (widget.type == ButtonType.outlined ||
        widget.type == ButtonType.text) {
      base = global ?? context.colorScheme.primary;
    } else {
      base = global ?? context.colorScheme.onSurface;
    }
    return widget.onPressed == null
        ? base.toOpacity(AppOpacity.disabled)
        : base;
  }
}

/// ⭐ 第 0 步（2026-10-10 ✓）：图标按钮的底色策略 —— 现状有三种并存 ✓，统一到此枚举 ✓；
/// 默认 `hover` = 与原先**逐字一致** ✓（不传的新参数一律不改变观感 ✓）。
enum IconButtonBackground { none, hover, always }

class _IconButton extends StatefulWidget {
  const _IconButton({
    super.key,
    required this.icon,
    // ⭐ 可空 ✓（支持禁用态 ✓；不传 ⇒ null = 禁用 ✓，与 M3 语义一致 ✓）
    this.onPressed,
    this.background = IconButtonBackground.hover,
    this.backgroundColor,
    this.active = false,
    this.activeColor,
    this.dense = false,
    this.padding,
    this.danger = false,
    this.size,
    this.color,
    this.tooltip,
    this.isLoading = false,
    this.behavior = HitTestBehavior.deferToChild,
  });

  final Widget icon;

  final VoidCallback? onPressed;

  final IconButtonBackground background;
  final Color? backgroundColor;
  final bool active;
  final Color? activeColor;
  final bool dense;
  final EdgeInsets? padding;
  final bool danger;

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
        // ⭐ 第 0 步 ✓：`active` / `danger` 仅**覆盖前景色** ✓（不传则为原行为 ✓）
        color:
            widget.color ??
            (widget.danger
                ? context.colorScheme.error
                : widget.active
                ? (widget.activeColor ?? context.colorScheme.primary)
                : context.colorScheme.primary),
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
        // ⭐ 水波统一（2026-10-10 ✓）：**真回调移入内层 `InkWell`** ✓ —— 与 `Button` 同一套做法 ✓。
        // 同一个手势识别器既负责水波又负责功能 ✓ ⇒ 不会出现"内层抢走手势、外层收不到点击"✗
        //（2026-10-10 曾因两层手势并存导致全仓按钮点不动 ✓）；此处外层仅保留 `behavior` 供命中测试 ✓。
        child: Tooltip(
          message: widget.tooltip ?? "",
          child: Container(
            decoration: BoxDecoration(
              // ⭐ 第 0 步 ✓：底色策略显式化 ✓（默认 hover 叠加 outlineVariant 的 0.4 强度 = 与原先**逐字一致** ✓）。
              // `always` 用 `iconOverlayColor()` ✓（**图标按钮的入口** ✓，勿与按钮 / 标签入口混用 ✓）。
              color: switch (widget.background) {
                IconButtonBackground.none => null,
                IconButtonBackground.always =>
                  widget.backgroundColor ?? iconOverlayColor(),
                IconButtonBackground.hover =>
                  isHover
                      ? (widget.backgroundColor ??
                            Theme.of(
                              context,
                            ).colorScheme.outlineVariant.toOpacity(0.4))
                      : null,
              },
              borderRadius: BorderRadius.circular((iconSize + 12) / 2),
            ),
            child: Material(
              // ⭐ 水波统一（2026-10-10 ✓）：`Material` 必须放在**底色之上** ✗→✓
              //（否则墨水被不透明底色盖住、点击看不到水波 ✗ —— 用户实测已确认此点 ✓）。
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular((iconSize + 12) / 2),
                onTap: widget.onPressed == null
                    ? null
                    : () {
                        if (widget.isLoading) return;
                        widget.onPressed!();
                      },
                // 水波/按压用**令牌透明度** ✓（不写字面量 ✗，守卫棘轮"只许降不许升" ✓）。
                splashColor: Theme.of(context).colorScheme.onSurface.toOpacity(
                  AppOpacity.tintStrengthDefault,
                ),
                highlightColor: Theme.of(
                  context,
                ).colorScheme.onSurface.toOpacity(AppOpacity.hoverInk),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.tiny),
                  child: icon,
                ),
              ),
            ),
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
    // （见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md）
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
