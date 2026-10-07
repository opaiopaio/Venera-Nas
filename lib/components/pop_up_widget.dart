part of 'components.dart';

class PopUpWidget<T> extends PopupRoute<T> {
  PopUpWidget(this.widget);

  final Widget widget;

  final _innerKey = GlobalKey<NavigatorState>();

  @override
  Color? get barrierColor => appdata.settings.customBackgroundActive
      ? Colors.transparent
      : Colors.black54;

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
    final decoration = secondaryPageDecoration();
    final tint = customSecondarySurfaceColor(context.colorScheme);
    final radius =
        borderRadius ??
        windowOverlayBorderRadius() ??
        BorderRadius.circular(AppRadius.md);
    final stack = Stack(
      children: [
        if (decoration != null)
          // 与全窗背景**逐像素对齐**的切片（此前是 `DecorationImage` 按自身盒子
          // fit → 小弹窗看到的是**缩略图** ✗）。只画不布局，见 [BackgroundSlice]。
          const Positioned.fill(child: BackgroundSlice()),
        if (tint != null) Positioned.fill(child: ColoredBox(color: tint)),
        if (fallbackToSurface && decoration == null && tint == null)
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
    // 二级页面表面：改为**分层叠加** ——
    //   底层：背景图装饰（有背景图时）
    //   中层：色调层（加深/变浅的半透明黑/白，或无图时的实色）
    //   上层：内容（Material 透明，避免"半透明 Material 底色"被当成实色渲染）
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
