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

    // ⭐ 与 `showSideBar` 同一判据：窄屏（竖屏）下该窗口会**铺满整屏** ✓（用户实测 ✓）。
    final fullScreen = !(MediaQuery.of(context).size.width > width);

    // ⭐ 修复（2026-10-09 用户指示 ✓）：与「探索页面 / 背景设置页」等**弹窗式二级页面**行为一致 ——
    // **竖屏（整屏）⇒ 半透明效果失效** ✗（恒用不透的兜底色 ✓）；**横屏 ⇒ 才受「侧边栏」那组设置控制** ✓
    //（含样式/背景/对比强度与半透明 ✓）。
    final followTheme = appdata.settings['secondaryPageFollowTheme'] == true;
    // ⭐ 修正（2026-10-09 用户指正 ✓）：**侧边栏设置全局受控** ✓ —— 上一版把整组控制在竖屏屏蔽掉了 ✗
    //（用户："其他控制项你不能给我屏蔽掉啊"✓）。现只在竖屏（整屏）时让**「样式」这一项强制不透明** ✓，
    // 背景（变深/变浅/无色调）与对比强度**照常生效** ✓。默认（跟随主题）仍与收藏页文件夹一致：不透的白底 ✓。
    final sideBarColor = followTheme
        ? backgroundPlaceholderColor(context.colorScheme)
        : sideBarSurfaceColor(context, forceOpaque: fullScreen);

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

    body = Container(
      decoration: BoxDecoration(
        borderRadius: showSideBar
            ? const BorderRadius.horizontal(left: Radius.circular(AppRadius.xl))
            : null,
        // ⭐ 2026-10-09（用户指示 ✓）：侧滑窗口的表面色改走**独立一组设置** ✓
        //（`sideBarSurfaceMode/Tint/TintStrength` ✓，与二级页面/菜单两套同构 ✓），
        // 受「二级页面/弹窗」页总开关 `secondaryPageFollowTheme` 控制 ✓（跟随主题 ⇒ 默认观感 ✓）。
        color: sideBarColor,
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
      child: GestureDetector(
        // ⭐ 修复（2026-10-09 用户实测 ✓）：**本层 `Material` 必须透明** ✗→✓ ——
        // 原先 `Material()` 不传 color ⇒ 取主题 `canvasColor`（**不透明表面色** ✗），
        // 把外层 `Container(decoration: color: sideBarColor)` 整个盖住 ⇒ 用户感受为"**这个窗口根本没法控制**" ✓
        //（白底恒亮、半透明/背景/对比强度全部无效 ✓）。改为透明后，设置才真正作用在观感上 ✓。
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
              // ⭐ 修复（2026-10-09 用户实测 ✓）：**侧滑窗口补铺背景切片** ✗→✓ ——
              // 共用组件原先只画 `sideBarSurfaceColor()` 一层**实色** ✗，而收藏页「文件夹选择」那条走
              // `SecondaryPageSurface(alwaysSliceBackground: true)` ✓ 会铺**与全局背景逐像素对齐的切片** ✓
              // ⇒ 两者观感不同（用户：漫画内收藏打开的侧滑窗口"并不受新的侧滑窗口控制"✓）。
              // 现给侧滑窗口也补上同一套切片 ⇒ **透出壁纸但不透出下层内容** ✓，与文件夹选择一致 ✓。
              child: Stack(
                children: [
                  // ⭐ 仅"启用自定义"时铺切片 ✓（默认与收藏页文件夹一致：白底不透 ✓）
                  if (!followTheme)
                    const Positioned.fill(child: BackgroundSlice()),
                  body,
                ],
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
    hasWallpaperSlice: false,
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
