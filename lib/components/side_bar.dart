part of 'components.dart';

class SideBarRoute<T> extends PopupRoute<T> {
  SideBarRoute(
    this.widget, {
    this.showBarrier = true,
    this.useSurfaceTintColor = false,
    this.dismissible = true,
    required this.width,
    this.addBottomPadding = true,
    this.addTopPadding = true,
  });

  final Widget widget;

  final bool showBarrier;

  final bool useSurfaceTintColor;

  final bool dismissible;

  final double width;

  final bool addTopPadding;

  final bool addBottomPadding;

  bool _barrierSawPointerDown = false;

  @override
  // ⭐ 2026-10-09（用户指示 ✓）：**变暗改为独立开关** `sideBarDim` ✓。
  // 未设置（默认）⇒ **保持既有行为** ✓（有自定义背景时不变暗、否则 black54 ✓）；
  // 设 true ⇒ 强制变暗 ✓；设 false ⇒ 强制不变暗 ✓。
  Color? get barrierColor {
    final dim = appdata.settings['sideBarDim'];
    if (dim == true) return Colors.black54;
    if (dim == false) return Colors.transparent;
    return showBarrier && !appdata.settings.customBackgroundActive
        ? Colors.black54
        : Colors.transparent;
  }

  @override
  bool get barrierDismissible => dismissible;

  @override
  String? get barrierLabel => "exit";

  @override
  TickerFuture didPush() {
    _barrierSawPointerDown = false;
    return super.didPush();
  }

  @override
  Widget buildModalBarrier() {
    if (!showBarrier) {
      return const SizedBox.shrink();
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.position == Offset.zero) {
          return;
        }
        _barrierSawPointerDown = true;
      },
      child: ModalBarrier(
        dismissible: dismissible,
        onDismiss: dismissible
            ? () {
                if (!_barrierSawPointerDown) {
                  return;
                }
                navigator?.maybePop();
              }
            : null,
        color: barrierColor,
        semanticsLabel: barrierLabel,
      ),
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // ⭐ 修复（2026-10-09 用户实测 ✓）：**建立设置依赖** ✗→✓ —— 原先此处没有 `AppSettingsScope.of(context)`，

    // 于是改动「二级页面/弹窗 → 侧边栏」那几项时该窗口不会重建 ⇒ 用户感受为"设置对它失效" ✓。

    AppSettingsScope.of(context);

    // ⭐ 与收藏页「文件夹选择」对齐（用户指示 ✓）：

    // · 默认（总开关＝跟随主题）⇒ 底用 `backgroundPlaceholderColor`（**白底不透** ✓，与文件夹选择一致 ✓）、不铺切片 ✗；

    // · 关闭总开关（启用自定义）⇒ 用侧边栏那组成品色 ✓、并铺背景切片 ✓（同 `SecondaryPageSurface` 的 tinted 门禁 ✓）。

    // ⭐ 本面板是否铺满整屏 ✓（面板宽度 vs 屏幕宽度 ✓）—— 传给统一表面组件决定"是否强制不透明" ✓
    final fullScreen = !(MediaQuery.of(context).size.width > width);

    bool showSideBar = MediaQuery.of(context).size.width > width;

    Widget body = widget;

    if (addTopPadding) {
      body = Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: body,
        ),
      );
    }

    final sideBarWidth = math.min(width, MediaQuery.of(context).size.width);

    // ⭐ 统一实现（2026-10-10 用户指正 ✓）：**表面只用 `SecondaryPageSurface` 这一套** ✗→✓ ——
    // 侧滑窗口与「弹窗式二级页面 / 收藏页文件夹选择」**共用同一个表面组件** ✓（切片、色调、底座、
    // 以及"跟随主题 / 竖屏强制不透明 / 启用自定义"等**全部门禁都只在那一处** ✓）。
    // 本组件只保留它真正独有的部分：**形态（贴边整高）与动画（左/右滑入）** ✓ ——
    // 用户原话："样式都一样只是弹出方向不同，为啥还要用两套实现方式写两套门控" ✓。
    body = Container(
      decoration: BoxDecoration(
        borderRadius: showSideBar
            ? const BorderRadius.horizontal(left: Radius.circular(AppRadius.xl))
            : null,
        // 仅阴影（底色/切片已交由 SecondaryPageSurface ✓，避免两处各画一份 ✗）
        boxShadow: context.brightness == ui.Brightness.dark
            ? [
                BoxShadow(
                  color: Colors.white.withAlpha(50),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxWidth: sideBarWidth),
      height: MediaQuery.of(context).size.height,
      child: SecondaryPageSurface(
        popupStyle: true,
        // ⭐ 面板铺满整屏时才强制不透明 ✓（与文件夹面板的判据一致 ✓）
        sideBarFullScreen: fullScreen,
        useSideBarSettings: true,
        alwaysSliceBackground: true,
        borderRadius: BorderRadius.zero,
        child: GestureDetector(
          child: Material(
            color: Colors.transparent,
            child: ClipRect(
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  MediaQuery.of(context).padding.right,
                  addBottomPadding
                      ? MediaQuery.of(context).padding.bottom +
                            MediaQuery.of(context).viewInsets.bottom
                      : 0,
                ),
                color: useSurfaceTintColor
                    ? Theme.of(context).colorScheme.surfaceTint.withAlpha(20)
                    : null,
                child: body,
              ),
            ),
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

    return Align(alignment: Alignment.centerRight, child: body);
  }

  @override
  Duration get transitionDuration => AppMotion.medium;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    var offset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: const Offset(0, 0),
    );
    return SlideTransition(
      position: offset.animate(
        CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
      ),
      child: child,
    );
  }
}

/// ⭐ 2026-10-09（用户指示 ✓）：**侧滑窗口/侧边栏**的成品表面色 —— 独立一组设置 ✓。
/// 受「二级页面/弹窗」页总开关 `secondaryPageFollowTheme` 控制 ✓：
/// 跟随主题（默认）⇒ 强制用**默认值**（不透明遮挡 / 变浅 / 0.22 ✓ = 用户"之前跟随主题的默认状态"✓）；
/// 关闭该总开关 ⇒ 用 `sideBarSurfaceMode/Tint/TintStrength` ✓。
/// ⭐ `forceOpaque`（用户 2026-10-09 指示 ✓）：**仅让「样式」这一项失效**（强制不透明 ✓），
/// **其余设置项（背景/对比强度）照常生效** ✓ —— 用于竖屏（窗口铺满整屏）时"半透明不透出内容" ✓。
Color sideBarSurfaceColor(BuildContext context, {bool forceOpaque = false}) {
  final followTheme = appdata.settings['secondaryPageFollowTheme'] == true;
  return secondarySurfaceColorFor(
    scheme: Theme.of(context).colorScheme,
    // ⭐ 竖屏（整屏）⇒ 仅**强制不透明** ✓（其余项不动 ✓）；其余情况照常受控 ✓
    mode: (forceOpaque || followTheme)
        ? 'opaque'
        : (appdata.settings['sideBarSurfaceMode'] as String? ?? 'opaque'),
    tint: followTheme
        ? 'lighten'
        : (appdata.settings['sideBarSurfaceTint'] as String? ?? 'lighten'),
    strength: followTheme
        ? AppOpacity.tintStrengthDefault
        : ((appdata.settings['sideBarSurfaceTintStrength'] as num?)
                  ?.toDouble() ??
              AppOpacity.tintStrengthDefault),
    // ⭐ 修复（2026-10-10 用户实测 ✓）：**有背景图时改传 true** ✗→✓ ——
    // 原先恒传 `false` ✗ ⇒ 本函数返回**成品不透明实色** ✓，而它被画在**切片之上** ⇒ **把壁纸盖住** ✗，
    // 用户感受为"选择不透明(遮挡)时页面还是纯白、没有背景图片" ✓。
    // 改传"是否存在背景图" ✓ ⇒ 有壁纸时只返回**色调层**（由切片负责背景 ✓），与二级页面同口径 ✓；
    // 无壁纸时仍走"背景色/主题底 ± 色调"的成品色 ✓（不透明遮挡 ✓）。
    hasWallpaperSlice: currentBackgroundImageFile() != null,
  );
}

Future<void> showSideBar(
  BuildContext context,
  Widget widget, {
  bool showBarrier = true,
  bool useSurfaceTintColor = false,
  bool dismissible = true,
  double width = 500,
  bool addTopPadding = true,
}) {
  return Navigator.of(context).push(
    SideBarRoute(
      widget,
      showBarrier: showBarrier,
      useSurfaceTintColor: useSurfaceTintColor,
      dismissible: dismissible,
      width: width,
      addTopPadding: addTopPadding,
      addBottomPadding: true,
    ),
  );
}
