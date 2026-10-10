part of 'components.dart';

const _minFlyoutWidth = 256.0;
const _minFlyoutHeight = 128.0;

class FlyoutController {
  Function? _show;

  void show() {
    if (_show == null) {
      throw "FlyoutController is not attached to a Flyout";
    }
    _show!();
  }
}

class Flyout extends StatefulWidget {
  const Flyout({
    super.key,
    required this.flyoutBuilder,
    required this.child,
    this.enableTap = false,
    this.enableDoubleTap = false,
    this.enableLongPress = false,
    this.enableSecondaryTap = false,
    this.withInkWell = false,
    this.borderRadius = 0,
    this.controller,
    this.navigator,
  });

  final WidgetBuilder flyoutBuilder;

  final Widget child;

  final bool enableTap;

  final bool enableDoubleTap;

  final bool enableLongPress;

  final bool enableSecondaryTap;

  final bool withInkWell;

  final double borderRadius;

  final NavigatorState? navigator;

  final FlyoutController? controller;

  @override
  State<Flyout> createState() => FlyoutState();

  static FlyoutState of(BuildContext context) {
    return context.findAncestorStateOfType<FlyoutState>()!;
  }
}

class FlyoutState extends State<Flyout> {
  @override
  void initState() {
    if (widget.controller != null) {
      widget.controller?._show = show;
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    if (widget.controller != null) {
      widget.controller?._show = show;
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.withInkWell) {
      return InkWell(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        onTap: widget.enableTap ? show : null,
        onDoubleTap: widget.enableDoubleTap ? show : null,
        onLongPress: widget.enableLongPress ? show : null,
        onSecondaryTap: widget.enableSecondaryTap ? show : null,
        child: widget.child,
      );
    }
    return GestureDetector(
      onTap: widget.enableTap ? show : null,
      onDoubleTap: widget.enableDoubleTap ? show : null,
      onLongPress: widget.enableLongPress ? show : null,
      onSecondaryTap: widget.enableSecondaryTap ? show : null,
      child: widget.child,
    );
  }

  void show() {
    var renderBox = context.findRenderObject() as RenderBox;
    var rect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    var navigator =
        widget.navigator ?? Navigator.of(context, rootNavigator: true);
    navigator.push(
      PageRouteBuilder(
        fullscreenDialog: true,
        barrierDismissible: true,
        opaque: false,
        // ⭐ N2 收尾（2026-10-09 用户实测"开关无变化"✓）：**必须显式把路由自身的遮罩设透明** ✗→✓ ——
        // `PageRouteBuilder` 继承 `ModalRoute`，其 `barrierColor` **默认是 `Color(0x80000000)`**
        // （≈50% 黑 ✓；**复查修正** ✗：此处原注释写成 `Colors.black54`（54%）不准确 ✓），
        // 而这里原先**没有覆写** ✗ → 于是暗罩有**两层**：① 路由默认那层 ~50% 黑（**不读开关** ✗）
        // ② 下方自绘的 30% 黑（已跟随 `secondaryMenuDim` ✓）→ **上面那层永远在暗** ✗
        // → 用户"关掉菜单变暗 / 关掉总开关"都**看不出变化** ✗（实测反馈 ✓）。
        // 现改为：路由层透明 ✓、**只保留下面这层跟随开关的自绘遮罩** ✓（淡入动画也保留 ✓）。
        // ⚠️ **复查修正** ✗：原注释写"（而非 null ✗）→ 命中区域仍在"的**因果不成立** ✗ ——
        // 点击外部关闭与 `barrierColor` **无关** ✓（barrier 组件始终由 `ModalRoute` 建立 ✓，
        // `barrierDismissible: true` ✓ 即生效 ✓）；真正拦住"点透到下层"的是
        // 下面那个 `GestureDetector(behavior: HitTestBehavior.opaque)` ✓（见本文件后段 ✓）。
        // 因此这里传 `Colors.transparent` 的唯一目的是**去掉视觉暗罩** ✓，不是为了命中 ✓。
        barrierColor: Colors.transparent,
        transitionDuration: _fastAnimationDuration,
        reverseTransitionDuration: _fastAnimationDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          var left = rect.left;
          var top = rect.bottom;

          if (left + _minFlyoutWidth > MediaQuery.of(context).size.width) {
            left = MediaQuery.of(context).size.width - _minFlyoutWidth;
          }
          if (top + _minFlyoutHeight > MediaQuery.of(context).size.height) {
            top = MediaQuery.of(context).size.height - _minFlyoutHeight;
          }

          Widget transition(
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget flyout,
          ) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.05),
                end: const Offset(0, 0),
              ).animate(animation),
              child: flyout,
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: navigator.pop,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, builder) {
                      // ⭐ 复查修复（2026-10-09 ✓）：同一插值里**重复调用了两次**同一函数 → 提取一次 ✓
                      //（纯重构，语义逐位不变 ✓；`secondaryMenuBarrierColor()` 恒为 const 色 ✓，无分配 ✓）。
                      final barrier = secondaryMenuBarrierColor();
                      return ColoredBox(
                        // ⭐ C6-新②（2026-10-09 审计 ✓）：原先**写死** `Colors.black @0.3` ✗ ——
                        // 完全无视应用内的「菜单变暗」（`secondaryMenuDim` ✓）开关 ✓ → 关掉它也照样变暗 ✗。
                        // 现改走**统一入口** `secondaryMenuBarrierColor()` ✓（与 `message.dart` /
                        // `follow_updates_page.dart` / `PopUpWidget.barrierColor` 同源 ✓ ——
                        // 遵循 E1 定的"暗罩逻辑集中一处、避免两条实现漂移"✓）。
                        // 保留原有"随动画渐显"✓：按它自身 alpha × `animation.value` ✓。
                        // **用户可见变化**：仅当你在「弹出式二级页面」里关掉"菜单变暗"时，
                        // Flyout 的暗罩**才会消失** ✓（开着时与旧观感一致 ✓）。
                        color: barrier.toOpacity(barrier.a * animation.value),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: left,
                right: 0,
                top: top,
                bottom: 0,
                child: transition(
                  context,
                  animation,
                  secondaryAnimation,
                  Align(
                    alignment: Alignment.topLeft,
                    child: widget.flyoutBuilder(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FlyoutContent extends StatelessWidget {
  const FlyoutContent({
    super.key,
    required this.title,
    required this.actions,
    this.content,
  });

  final String title;

  final Widget? content;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：本控件的外观由设置算出 → 设置变化时由框架精准重建
    // （见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    return IntrinsicWidth(
      child: BlurEffect(
        borderRadius:
            windowOverlayBorderRadius() ?? BorderRadius.circular(AppRadius.md),
        child: Material(
          borderRadius: BorderRadius.circular(AppRadius.md),
          type: MaterialType.card,
          color: appdata.settings.customBackgroundActive
              ? windowOverlayColor()
              : context.colorScheme.surface.toOpacity(0.82),
          child: Container(
            constraints: const BoxConstraints(minWidth: _minFlyoutWidth),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpace.sm,
              horizontal: AppSpace.lg,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: context.brightness == ui.Brightness.dark
                  ? Border.all(color: context.colorScheme.outlineVariant)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (content != null) content!,
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [const Spacer(), ...actions],
                ),
              ],
            ),
          ),
        ).paddingAll(4),
      ),
    );
  }
}
