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
    this.clip = true,
    this.popupStyle = true,
    this.alwaysSliceBackground = false,
  });

  final Widget child;

  /// 不传则跟随圆角设置（默认 `AppRadius.md`）。
  final BorderRadius? borderRadius;

  /// ⭐ AP1-A4（审计 ✓）：此处原有 `final bool fallbackToSurface` ✗ —— 它在 `build` 里
  /// **从未被读取** ✓（真实底色由 `needSurface = popupStyle || !backgroundFeatureActive` ✓ 决定 ✓）
  /// → 属**死参数** ✗（`PopUpWidgetScaffold` 传 `false` 与测试传 `false` 都不影响结果 ✓）
  /// → 已删除 ✓（零行为影响 ✓）。

  /// 是否用 [ClipRRect] 按 `borderRadius` 裁切。
  /// `PopUpWidgetScaffold` 的形状/圆角由路由 decoration 提供 → 传 `false`（等价迁移）✓
  final bool clip;

  /// ⭐ Q2（用户反馈 ✓）：是否**弹出式**二级页面（`ContentDialog` / 菜单这类**小浮层** ✓）。
  /// - `true`（**默认** ✓，`ContentDialog` 等）→ 叠加**色调加深**与背景装饰 ✓；
  /// - `false`（`PopUpWidgetScaffold` = **整页式**二级页面 ✓）→ **不叠加** ✗。
  ///
  /// 用户要求 ✓："色调加深只作用给**弹窗式**二级页面，而不是给**整页式**这种" ✓
  ///（正式名参考：弹出式 = Dialog / Modal Overlay / PopupRoute ✓；
  ///  整页式 = Full-screen route / Pushed page ✓）。
  final bool popupStyle;

  /// ⭐（2026-10-09 用户指示）：即使「弹出式二级页面」体系**关闭**，也**照常铺背景切片** ——
  /// 用于**浮层**类表面（收藏页窄屏侧栏）。切片由 [BackgroundSlice]**自绘** ⇒ 背景可见、下层内容不透出；
  /// 色调仍**跟随**该体系（体系关闭时 tint 为 null ⇒ 不叠色调）。默认 false ⇒ 其它调用方零变化。
  final bool alwaysSliceBackground;

  @override
  Widget build(BuildContext context) {
    AppSettingsScope.of(context);
    // ⭐ P2（用户反馈 ✓）：**跟随系统主题**时 —— 不画背景切片 ✗、不做色调 ✗、
    // 强制补一层**主题表面色** ✓（= 遮挡下面内容 ✓，且不调色不变深 ✓）。
    final followTheme = appdata.settings['secondaryPageFollowTheme'] == true;
    // ⭐ P2：跟随主题 → 不画切片/不做色调，强制补主题表面色 ✓（= 遮挡 ✓）
    // ⭐ Q2：**整页式**（`popupStyle: false`）不叠加色调/背景装饰 ✗ —— 用户要求
    // "色调加深只作用给弹出式二级页面" ✓；此时它由**自身路由的 decoration** 负责底色 ✓。
    final tinted = !followTheme && popupStyle;
    final decoration = secondaryPageDecoration();
    final tint = customSecondarySurfaceColor(context.colorScheme);
    // ⭐ W2（用户选定方案 B ✓）：**整页式永远透出背景** ✓、**完全不受本节选项影响** ✗ ——
    // - **有背景**（背景图/背景底色 ✓）→ **不铺任何底** ✓（露出全局背景 ✓，用户实测
    //   "整页式被纯白底色覆盖、不显示背景" ✗）；
    // - **无背景** → 退回**主题表面色** ✓（此时没有"背景"可露 ✓；若也不铺底会透出下层页面 ✗）；
    // - 弹出式 ✓ 照旧：有底（遮挡 ✓）+ 可调模式/色调 ✓。
    // 注意 ✓：`decoration`（壁纸切片）与 `tint`（色调 ✓）都只对**弹出式**生效 ✗（`tinted` ✓），
    // 所以整页式**天然不受**这两个选项影响 ✓。
    final needSurface = popupStyle || !appdata.settings.backgroundFeatureActive;
    // ⭐ U1（用户反馈 ✓）：底**按模式给透明度** ✓，色调**混入底**而不是叠蒙层 ✗。
    // - `opaque`（不透明 ✓）→ 不透明主题表面色 ✓（遮挡 ✓）；
    // - `transparent`（半透明 ✓）→ 用 `AppOpacity.hint` ✓ 的底 ✓，**透出下层内容** ✓
    //   （用户实测："切换成半透明，二级窗口就变白底了，不会透出来" ✗）；
    // - 色调用 `Color.alphaBlend` **混进底色** ✓ → `darken` = **更深的面板** ✓、
    //   `lighten` = 更浅的面板 ✓（用户实测："变深一打开就变灰色界面" ✗ = 不透明白底 + 黑色蒙层 ✗）。
    // ⭐ V1（用户反馈 ✓）：本节的选项（**模式** + **深浅** ✓）**只作用于弹出式** ✓ ——
    // 整页式（`popupStyle == false` ✓：设置子页 / 探索页面 / 分类页面…）**完全不受影响** ✗，
    // 恒用**不透明主题表面色** ✓（有背景图时仍由壁纸切片负责 ✓）。
    // 用户实测："弹出式二级页面的选项会对整页式二级页面造成影响" ✗
    //（根因：上一版只把**色调**限定给弹出式 ✓，**模式没限定** ✗ → 整页式也变半透明 ✗）。
    // （`mode` / `translucent` 已不再在本地使用 ✓ —— 模式判断在
    //  `customSecondarySurfaceColor()` 内部完成 ✓，这里只消费它的成品色 ✓。）
    // ⭐ V1②（用户反馈 ✓）：`customSecondarySurfaceColor()` 返回的**已经是成品表面色** ✓
    //（`window_overlay.dart` 内部已 `return Color.alphaBlend(tintColor, base)` ✓；
    //  半透明模式 / 有背景图时则返回**色调层本身** ✓）→ 这里**直接当底用** ✓。
    // ⚠️ 之前我又 `alphaBlend(tint, base)` 混了一次 ✗ → **色调叠两遍** ✗ →
    // 无背景时"深浅变得很诡异" ✓（用户实测 ✓）。
    // ⭐ W1（用户澄清 ✓）：色调**本身就是成品** ✓ ——
    // 不透明模式下它是"**以当前背景色为主**混出色调"的实色 ✓；
    // 半透明模式下它是叠在背景上的**遮罩**（泛白 / 发黑 / 不调整=浅白 ✓，见 `window_overlay.dart` ✓）。
    // → 这里**直接当底用** ✓：不再二次混合 ✗（V1② ✓）、也**不要**擅自改它的透明度 ✗
    //（那会把用户设的强度冲掉 ✗，U1 的旧做法已废弃 ✗）。
    // ⭐ 修复（2026-10-09 用户实测）：`followTheme`（用户所说"开关打开 = 跟随系统"）时，
    // 底色必须是**主题表面色** —— 原写法 `base = tint` 与本节注释自相矛盾：
    // `customSecondarySurfaceColor()` 在**有背景图**时返回的是**色调层本身**（半透明，
    // 设计上需配合下方 `BackgroundSlice` 切片刻画），而 `followTheme` 又**不画切片**
    // （`tinted = !followTheme && popupStyle` = false）⇒ **既无底又无切片** ⇒ 整块透出
    // 下层内容（用户实测：窄屏收藏页侧栏透出后面的漫画列表）。
    // 现改为：`followTheme` 时不使用色调，直接补主题表面色（＝注释所述语义）。
    final base =
        (popupStyle && !followTheme ? tint : null) ??
        context.colorScheme.surface;
    final radius =
        borderRadius ??
        windowOverlayBorderRadius() ??
        BorderRadius.circular(AppRadius.md);
    // ⭐（2026-10-09 用户指示）：`alwaysSliceBackground` = 即使本体系**关闭**，也照常铺背景切片
    //（"透过背景、不透出下层内容"；切片自绘）。默认 false ⇒ 其它调用方逐字不变。
    // ⭐ 修复（2026-10-09 用户实测）：**整页式**（`popupStyle == false`，即 PopUpWidgetScaffold
    // 这类设置子页 / 探索页面 / 分类页面 / 网络收藏页面 / 搜索源）在**有背景图**时原先
    // "不画切片 ✗ + 不铺底 ✗" ⇒ **全透明** ✗；独占一屏时只是透出壁纸 ✓，但**被放在别的页面之上**
    //（右栏内层导航等）就会**整片透出下层内容** ✗（用户实测：设置页与下层内容重叠 ✓）。
    // 现改为：**只要有背景图就铺切片** ✓（切片自绘 ⇒ 壁纸照常 ✓、下层不透出 ✓）。
    // 跟随系统主题时仍**不画切片** ✗（尊重该设置 ✓）；色调仍**只给弹出式** ✗（整页式不叠 ✓）。
    final showSlice =
        !followTheme &&
        currentBackgroundImageFile() != null &&
        (alwaysSliceBackground || decoration != null || !popupStyle);
    final stack = Stack(
      children: [
        // ⭐ S1：**不透明底必须在最底层** ✓ —— 放在色调/装饰之后会**盖住色调** ✗
        //（用户实测："打开加深也不会变深" ✗）。
        if (needSurface) Positioned.fill(child: ColoredBox(color: base)),
        // ⭐（2026-10-09 用户指示）：`alwaysSliceBackground` = 即使本体系**关闭**，
        // 也照常铺**背景切片**（"透过背景、不透出下层内容"；切片自绘）。
        // 原调用方**逐字不变**（默认 false ⇒ 条件与原来完全相同）。
        if (showSlice) ...[
          // 与全窗背景**逐像素对齐**的切片（此前是 `DecorationImage` 按自身盒子
          // fit → 小弹窗看到的是**缩略图**）。只画不布局，见 [BackgroundSlice]。
          const Positioned.fill(child: BackgroundSlice()),
          // 有**壁纸切片**时，色调叠在**切片之上**（语义 = 把壁纸调深/调浅）；
          // 无切片时色调已**混入底色**（见上），不重复叠。
          if (tinted && tint != null)
            Positioned.fill(child: ColoredBox(color: tint)),
        ],
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
    // ⭐ T1（用户反馈 ✓）：本弹层是否按**弹出式**（对话框类 ✓，如**色盘**）对待 ——
    // 影响是否叠加**色调加深** ✓。默认 `false` = **整页式**设置页 ✓（Q2 ✓，不叠色调 ✗）；
    // 色盘这类小浮层传 `true` ✓（用户实测"打开二级窗口控制后，依然无法控制色盘" ✗）。
    this.popupStyle = false,
    super.key,
  });

  final Widget body;
  final List<Widget>? tailing;
  final String title;
  final bool popupStyle;

  @override
  State<PopUpWidgetScaffold> createState() => _PopUpWidgetScaffoldState();
}

class _PopUpWidgetScaffoldState extends State<PopUpWidgetScaffold> {
  bool top = true;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：二级页面样式/色调/强度变化时由框架精准重建本弹层表面
    // （取代历史上的整树遍历刷新；见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md）
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
      // ⭐ AP1-A4：`fallbackToSurface` 死参数已删除 ✗（底色由 `needSurface` 决定 ✓）
      clip: false,
      // ⭐ Q2/T1：沿用宿主传入的分类 ✓ —— 整页式设置页 `false` ✗（不叠色调 ✓）；
      // 色盘等弹出式传 `true` ✓（可被色调控制 ✓）。
      popupStyle: widget.popupStyle,
      child: content,
    );
  }
}
