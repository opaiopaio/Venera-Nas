part of 'components.dart';

/// ⭐ E1：二级菜单/弹层**暗罩**的统一判定 ✓ —— 由外观设置「突出二级菜单」控制 ✓。
///
/// - 开关 **开** → `Colors.black54` ✓（周围变暗 ✓）；
/// - 开关 **关** → `Colors.transparent` ✓（统一无暗罩 ✓；遮罩仍存在 ✓，点击外部关闭不受影响 ✓）；
/// - **未设置** → 保持原有行为 ✓（有自定义背景时不变暗、否则变暗 ✓，零回归 ✓）。
///
/// 用法 ✓：
/// - `PopUpWidget.barrierColor` 直接用它 ✓；
/// - `showDialog(...)` 若传的是 **`App.rootContext`** 这类"主题之上"的 context ✗，
///   主题层的 `dialogTheme.barrierColor` **取不到** ✗ → 必须在调用点**显式传**
///   `barrierColor: secondaryMenuBarrierColor()` ✓（用户实测：追更页「立即检查」的
///   选文件夹弹窗不受开关控制 ✗，根因即此 ✓）。
Color secondaryMenuBarrierColor() {
  final dim = appdata.settings['secondaryMenuDim'];
  if (dim == true) return Colors.black54;
  if (dim == false) return Colors.transparent;
  return appdata.settings.customBackgroundActive
      ? Colors.transparent
      : Colors.black54;
}

class PopUpWidget<T> extends PopupRoute<T> {
  PopUpWidget(this.widget);

  final Widget widget;

  final _innerKey = GlobalKey<NavigatorState>();

  @override
  // E1：暗罩统一走 [secondaryMenuBarrierColor] ✓（逻辑集中一处 ✓，避免两条实现漂移 ✗）。
  Color? get barrierColor => secondaryMenuBarrierColor();

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "exit";

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    var height = MediaQuery.of(context).size.height * 0.9;
    bool showPopUp = MediaQuery.of(context).size.width > 500;
    Widget body = PopupIndicatorWidget(
      child: Container(
        decoration: showPopUp
            ? BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
                boxShadow: context.brightness == ui.Brightness.dark
                    ? [
                        BoxShadow(
                          color: Colors.white.withAlpha(50),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              )
            : null,
        clipBehavior: showPopUp ? Clip.antiAlias : Clip.none,
        width: showPopUp ? 500 : double.infinity,
        height: showPopUp ? height : double.infinity,
        child: ClipRect(
          child: Navigator(
            key: _innerKey,
            onGenerateRoute: (settings) =>
                MaterialPageRoute(builder: (context) => widget),
            onDidRemovePage: (page) {},
          ),
        ),
      ),
    );
    if (App.isIOS) {
      body = IOSBackGestureDetector(
        enabledCallback: () => true,
        gestureWidth: 20.0,
        onStartPopGesture: () =>
            IOSBackGestureController(controller!, navigator!),
        child: body,
      );
    }
    if (showPopUp) {
      return MediaQuery.removePadding(
        removeTop: true,
        context: context,
        child: Center(child: body),
      );
    }
    return body;
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(
        Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.ease)),
      ),
      child: child,
    );
  }
}

class PopupIndicatorWidget extends InheritedWidget {
  const PopupIndicatorWidget({super.key, required super.child});

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;

  static PopupIndicatorWidget? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PopupIndicatorWidget>();
  }
}

Future<T> showPopUpWidget<T>(BuildContext context, Widget widget) async {
  return await Navigator.of(
    context,
    rootNavigator: true,
  ).push(PopUpWidget(widget));
}

/// 二级页面（弹层）的**统一表面**：底层背景图装饰 + 中层色调 + 上层透明内容层。
///
/// `PopUpWidgetScaffold`（完整二级页）与 `ContentDialog`（输入框 / 确认框 / 消息框）
/// 共用，保证**所有**二级菜单都跟随「二级页面样式 / 色调 / 强度」，圆角跟随
/// 「窗口/按钮背景」的直角/圆角设置。
///
/// - 二级页面体系未启用（样式 = `off`）时，`secondaryPageDecoration()` 与
///   `customSecondarySurfaceColor()` 均为 null → 退回**主题表面色**（零回归 ✓）。
/// - 依赖 `AppSettingsScope`：设置一改即时重建（见 `11-refresh-mechanism.md`）。
class SecondaryPageSurface extends StatelessWidget {
  const SecondaryPageSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.fallbackToSurface = true,
    this.clip = true,
  });

  final Widget child;

  /// 不传则跟随圆角设置（默认 `AppRadius.md`）。
  final BorderRadius? borderRadius;

  /// 二级页面体系未启用时，是否补一层主题表面色。
  /// - `ContentDialog`：需要（否则弹窗会透明透出下层内容）→ 保持默认 `true` ✓
  /// - `PopUpWidgetScaffold`：不需要（它依赖**自身路由的 decoration**，见其 buildPage）
  ///   → 传 `false`，与迁移前行为一致 ✓
  final bool fallbackToSurface;

  /// 是否用 [ClipRRect] 按 `borderRadius` 裁切。
  /// `PopUpWidgetScaffold` 的形状/圆角由路由 decoration 提供 → 传 `false`（等价迁移）✓
  final bool clip;

  @override
  Widget build(BuildContext context) {
    AppSettingsScope.of(context);
    // ⭐ P2（用户反馈 ✓）：**跟随系统主题**时 —— 不画背景切片 ✗、不做色调 ✗、
    // 强制补一层**主题表面色** ✓（= 遮挡下面内容 ✓，且不调色不变深 ✓）。
    final followTheme = appdata.settings['secondaryPageFollowTheme'] == true;
    final decoration = secondaryPageDecoration();
    final tint = customSecondarySurfaceColor(context.colorScheme);
    final radius =
        borderRadius ??
        windowOverlayBorderRadius() ??
        BorderRadius.circular(AppRadius.md);
    final stack = Stack(
      children: [
        if (decoration != null && !followTheme)
          // 与全窗背景**逐像素对齐**的切片（此前是 `DecorationImage` 按自身盒子
          // fit → 小弹窗看到的是**缩略图** ✗）。只画不布局，见 [BackgroundSlice]。
          const Positioned.fill(child: BackgroundSlice()),
        if (tint != null && !followTheme)
          Positioned.fill(child: ColoredBox(color: tint)),
        if (followTheme ||
            (fallbackToSurface && decoration == null && tint == null))
          // 跟随主题 → 主题表面色 ✓（遮挡 ✓）；体系未启用 → 同样兜底（零回归 ✓）。
          Positioned.fill(
            child: ColoredBox(color: context.colorScheme.surface),
          ),
        Material(color: Colors.transparent, child: child),
      ],
    );
    return clip ? ClipRRect(borderRadius: radius, child: stack) : stack;
  }
}

class PopUpWidgetScaffold extends StatefulWidget {
  const PopUpWidgetScaffold({
    required this.title,
    required this.body,
    this.tailing,
    super.key,
  });

  final Widget body;
  final List<Widget>? tailing;
  final String title;

  @override
  State<PopUpWidgetScaffold> createState() => _PopUpWidgetScaffoldState();
}

class _PopUpWidgetScaffoldState extends State<PopUpWidgetScaffold> {
  bool top = true;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：二级页面样式/色调/强度变化时由框架精准重建本弹层表面
    // （取代历史上的整树遍历刷新；见 doc-private/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    // 内容（Material 透明，避免"半透明 Material 底色"被当成实色渲染）；
    // 表面（背景切片 + 色调层）统一由 build 末尾的 [SecondaryPageSurface] 提供 ✓
    Widget content = Material(
      color: Colors.transparent,
      child: Column(
        children: [
          Container(
            height: 56 + context.padding.top,
            padding: EdgeInsets.only(top: context.padding.top),
            width: double.infinity,
            decoration: BoxDecoration(
              color: top
                  ? null
                  : Theme.of(context).colorScheme.surfaceTint.withAlpha(20),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Tooltip(
                  message: "Back".tl,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_sharp),
                    onPressed: () =>
                        context.canPop() ? context.pop() : App.pop(),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (widget.tailing != null) ...widget.tailing!,
                const SizedBox(width: 8),
              ],
            ),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (notifications) {
              if (notifications.metrics.axisDirection != AxisDirection.down) {
                return false;
              }
              if (notifications.metrics.pixels ==
                      notifications.metrics.minScrollExtent &&
                  !top) {
                setState(() {
                  top = true;
                });
              } else if (notifications.metrics.pixels !=
                      notifications.metrics.minScrollExtent &&
                  top) {
                setState(() {
                  top = false;
                });
              }
              return false;
            },
            child: MediaQuery.removePadding(
              removeTop: true,
              context: context,
              child: Expanded(child: widget.body),
            ),
          ),
          SizedBox(
            height:
                MediaQuery.of(context).viewInsets.bottom -
                        0.05 * MediaQuery.of(context).size.height >
                    0
                ? MediaQuery.of(context).viewInsets.bottom -
                      0.05 * MediaQuery.of(context).size.height
                : 0,
          ),
        ],
      ),
    );
    // 统一表面（与 ContentDialog 共用同一实现，见 [SecondaryPageSurface]）：
    // fallbackToSurface: false —— 本二级页依赖**自身路由的 decoration**（不一致地补底会变样 ✗）；
    // clip: false —— 形状/圆角由路由 decoration 提供（与迁移前行为一致 ✓）。
    return SecondaryPageSurface(
      fallbackToSurface: false,
      clip: false,
      child: content,
    );
  }
}
