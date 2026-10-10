part of 'components.dart';

class Appbar extends StatefulWidget implements PreferredSizeWidget {
  const Appbar({
    required this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.style = AppbarStyle.blur,
    super.key,
  });

  final Widget title;

  final Widget? leading;

  final List<Widget>? actions;

  final Color? backgroundColor;

  final AppbarStyle style;

  @override
  State<Appbar> createState() => _AppbarState();

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

class _AppbarState extends State<Appbar> {
  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：顶栏底色/毛玻璃随设置变化时精准重建
    AppSettingsScope.of(context);
    var content = Container(
      decoration: BoxDecoration(
        color: customBackgroundAware(
          widget.backgroundColor ?? context.colorScheme.surface.toOpacity(0.86),
        ),
      ),
      constraints: BoxConstraints(
        minHeight: _kAppBarHeight + context.padding.top,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          widget.leading ??
              Tooltip(
                message: "Back".tl,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
          const SizedBox(width: 16),
          Expanded(
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 20),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: widget.title,
            ),
          ),
          ...?widget.actions?.map(
            (e) => appdata.settings.customBackgroundActive
                // 启用「窗口/按钮背景」时按钮自带底色块，这里补间距避免贴在一起
                // ⭐ 修复（2026-10-09 用户实测 ✓）：**竖屏（窄屏）下顶栏按钮间距加大** ✗→✓ ——
                // 原先仅在有「窗口/按钮背景」时补 `AppSpace.tiny`（≈4 ⇒ 相邻仅 8px）✗，无背景时更是 0 ✗，
                // 竖屏下「搜索 / 设置」这类相邻按钮会挤在一起 ✓（用户反馈 ✓）。
                // 现统一给间距：**窄屏 `AppSpace.sm`（约 2 倍）** ✓、宽屏沿用 `AppSpace.tiny` ✓（宽屏观感不变 ✓）。
                ? Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.width < changePoint
                          ? AppSpace.sm
                          : AppSpace.tiny,
                    ),
                    child: e,
                  )
                : e,
          ),
          const SizedBox(width: 8),
        ],
      ).paddingTop(context.padding.top),
    );
    return _headerSurface(context, widget.style, content);
  }
}

enum AppbarStyle { blur, shadow }

/// 顶栏底：**不透明的「背景切片」**。
///
/// 启用自定义背景（背景图/底色）时，顶栏直接画出与全窗背景**同一份**的
/// [AppBackground]：按**自己在窗口里的真实位置**（`localToGlobal`）平移整窗尺寸的
/// 背景层 —— 横向（侧栏/双栏偏移）与纵向（标题栏让位）都能**严格对齐、无缝**；
/// 静止时与"透明露出背景"外观一致，内容滚上来则被**实心挡住**，没有任何动画效果。
///
/// 未启用背景时退回主题表面色，保证顶栏**始终不透明** ✓。
///
/// ⚠️ **不要在"未启用背景"时加毛玻璃** ✗ —— 纯色背景下的模糊会糊在滚动内容上、
/// 观感很脏 ✗（用户实测反馈：带暗罩的二级菜单，其顶栏在纯色背景下出现毛玻璃 ✗）。
/// 早前这里曾有 `style == blur && !AppBackground.isActive → BlurEffect` ✗，已移除 ✓。
Widget _headerSurface(BuildContext context, AppbarStyle style, Widget body) {
  // `style` 保留在签名里以备将来扩展样式 ✓；当前统一走"不透明表面" ✓。
  return _HeaderSurface(body: body);
}

class _HeaderSurface extends StatefulWidget {
  const _HeaderSurface({required this.body});

  final Widget body;

  @override
  State<_HeaderSurface> createState() => _HeaderSurfaceState();
}

class _HeaderSurfaceState extends State<_HeaderSurface> {
  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：背景切片/毛玻璃/圆角随设置变化时精准重建
    AppSettingsScope.of(context);

    // ⚠️ **弹层（二级菜单）直接返回内容，不画任何底**：
    // 弹层自身有表面与圆角（`PopUpWidgetScaffold` 的 secondaryPageDecoration），
    // 在这里画不透明底色会把弹层顶部压成**直角** ✗，画背景切片则会盖住弹层表面 ✗
    // （均为用户实测报告）。加这层底之前的行为就是"内容直接铺在弹层表面上" ✓
    if (ModalRoute.of(context) is PopupRoute) return widget.body;
    return ClipRect(
      child: Stack(
        // 用 alignment 居中（**不要** StackFit.expand）：后者要求约束有界，
        // 顶栏被放进弹层/滚动容器这类无界上下文时会撑爆布局，真机上表现为
        // "中间出现一条可以上下滚动的背景带"。
        alignment: Alignment.center,
        children: [
          // 不透明兜底（背景底色可能是半透明的）
          Positioned.fill(
            child: // ⭐ 修复（2026-10-09 用户 Android 实测 ✓）：本底原先写死 `colorScheme.surface` ✗
                // ⇒ 背景图**未就绪时**这里会露出**白块**（浅色主题）✓；改用与全局背景**同口径**的兜底色 ✓。
                ColoredBox(
                  // ⭐ 修复（2026-10-09 用户 Android 实测 ✓）：背景体系**开启时本层应当透明** ✓ ——

                  // 否则切片尚未就绪的那几帧会露出**白色**（用户："背景被压在下面，白色消失背景出现"✓）；关闭背景时退回同口径兜底色 ✓。
                  color:
                      customBackgroundAware(
                        backgroundPlaceholderColor(context.colorScheme),
                      ) ??
                      Colors.transparent,
                ),
          ),
          if (AppBackground.isActive)
            // 背景切片：**只画不布局**的自绘（见 [_HeaderBackground] 注释）。
            // 仅用于**页面**顶栏；弹层在上面已提前返回（不画切片/底色）。
            const Positioned.fill(child: BackgroundSlice()),
          widget.body,
        ],
      ),
    );
  }
}

class SliverAppbar extends StatelessWidget {
  const SliverAppbar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.radius = 0,
    this.style = AppbarStyle.blur,
  });

  final Widget? leading;

  final Widget title;

  final List<Widget>? actions;

  final double radius;

  final AppbarStyle style;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _MySliverAppBarDelegate(
        leading: leading,
        title: title,
        actions: actions,
        topPadding: MediaQuery.of(context).padding.top,
        fontScale: _barTextScale(context),
        radius: radius,
        style: style,
      ),
    );
  }
}

const _kAppBarHeight = 52.0;

/// ⭐ 本轮（用户实测反馈 ✓）：顶栏高度用的缩放系数 —— **必须与文字同源** ✓，
/// 即取环境 `MediaQuery` 的 `textScaler` ✓（`main.dart` 的 `MaterialApp.builder` 注入的就是它 ✓）。
///
/// 为什么不用 `globalFontScale()` ✗：那只反映设置页的**app 内缩放** ✓，而文字**实际**生效的
/// 系数由 `main.dart` 写进 `MediaQuery` ✓ —— app 内缩放恰为 1 时该处**不注入** ⇒
/// 平台/系统字号会穿透进来 ✓。两种来源在 ① app 内缩放小于 1 ✓、
/// ② app 内缩放为 1 而系统字号不为 1 ✓ 时会分叉 ⇒ 表现为"文字变了而顶栏没变" ✗。
/// 改用同一来源后顶栏与文字始终同步 ✓。
///
/// 数值观感 ✓：app 内缩放与系统字号都为 1 时本系数就是 1 ⇒ 高度与改前**完全一致** ✓。
double _barTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1.0);

class _MySliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget? leading;

  final Widget title;

  final List<Widget>? actions;

  final double topPadding;

  /// ⭐ 本轮：顶栏高度用的缩放系数 ✓ —— 由 [SliverAppbar] 从环境 `MediaQuery`
  /// 取得（与文字同源 ✓，见 `_barTextScale` ✓）；`minExtent`/`maxExtent` 是
  /// **无 context 的 getter** ✗，故必须这样传进来 ✓。
  final double fontScale;

  final double radius;

  final AppbarStyle style;

  _MySliverAppBarDelegate({
    this.leading,
    required this.title,
    this.actions,
    required this.topPadding,
    required this.fontScale,
    this.radius = 0,
    this.style = AppbarStyle.blur,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    var body = Row(
      children: [
        const SizedBox(width: 8),
        leading ??
            (Navigator.of(context).canPop()
                ? Tooltip(
                    message: "Back".tl,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  )
                : const SizedBox()),
        const SizedBox(width: 16),
        Expanded(
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 20),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: title,
          ),
        ),
        ...?actions?.map(
          (e) => appdata.settings.customBackgroundActive
              // ⭐ 修复（2026-10-09 用户实测 ✓）：**竖屏（窄屏）下顶栏按钮间距加大** ✗→✓ ——
              // 原先仅在有「窗口/按钮背景」时补 `AppSpace.tiny`（≈4 ⇒ 相邻仅 8px）✗，无背景时更是 0 ✗，
              // 竖屏下「搜索 / 设置」这类相邻按钮会挤在一起 ✓（用户反馈 ✓）。
              // 现统一给间距：**窄屏 `AppSpace.sm`（约 2 倍）** ✓、宽屏沿用 `AppSpace.tiny` ✓（宽屏观感不变 ✓）。
              ? Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.width < changePoint
                        ? AppSpace.sm
                        : AppSpace.tiny,
                  ),
                  child: e,
                )
              : e,
        ),
        const SizedBox(width: 8),
      ],
    ).paddingTop(topPadding);

    return SizedBox.expand(child: _headerSurface(context, style, body));
  }

  @override
  double get maxExtent => (_kAppBarHeight + topPadding) * fontScale;

  @override
  double get minExtent => (_kAppBarHeight + topPadding) * fontScale;

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _MySliverAppBarDelegate ||
        leading != oldDelegate.leading ||
        title != oldDelegate.title ||
        actions != oldDelegate.actions ||
        topPadding != oldDelegate.topPadding ||
        fontScale != oldDelegate.fontScale ||
        radius != oldDelegate.radius ||
        style != oldDelegate.style;
  }
}

class AppTabBar extends StatefulWidget {
  const AppTabBar({
    super.key,
    this.controller,
    required this.tabs,
    this.actionButton,
    this.withUnderLine = true,
  });

  final TabController? controller;

  final List<Tab> tabs;

  final Widget? actionButton;

  final bool withUnderLine;

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar> {
  late TabController _controller;

  late List<GlobalKey> keys;

  static const _kTabHeight = AppTopBar.tabHeight; // AA1：令牌化（原裸数字 ✗）

  /// AA1 令牌化：**按钮本身的大小高度**由这里决定 ✓ —— 垂直内边距由 `AppSpace.tiny`
  /// 收到 `AppSpace.xs` ✓ = 上下各收一点 = **按钮变小** ✓。
  /// ⚠️ 注意 ✓：注释**不能写在参数中间** ✗ —— 外观守卫的"裸间距数值"规则会扫描
  /// 内边距构造函数（如对称内边距）到第一个右括号之间的**任何数字** ✓（注释里的编号也算 ✗）。
  /// ⭐ AA1（用户实测 ✓）：顶栏「漫画源标签」与「+ 加号按钮」**共用同一套内边距** ✓ ——
  /// 抽成常量可避免两者漂移 ✗（此前 chip 用 `7/7/1/3`、加号用 `AppSpace.md` 水平 ✗ →
  /// 用户看到"和加号按钮间距不对" ✗、"加号没对齐/小扁扁" ✗）。
  static const tabItemPadding = EdgeInsets.only(
    left: 7,
    right: 7,
    top: 1,
    bottom: 3,
  );

  static const tabPadding = EdgeInsets.symmetric(
    horizontal: AppSpace.md,
    vertical: AppSpace.xs,
  );

  static const tabRadius = 8.0;

  _IndicatorPainter? painter;

  var scrollController = ScrollController();

  var tabBarKey = GlobalKey();

  var offsets = <double>[];

  /// ⭐ AP1-A3（审计 ✓）：记录**当前已订阅**的 animation ✓ ——
  /// 便于在重建/更换 controller 前 `removeListener` ✓（原先只 addListener 不 remove ✗
  /// → 依赖变化/换 controller 时监听**逐次累积** ✓）。
  Animation<double>? _listenedAnimation;

  @override
  void initState() {
    keys = widget.tabs.map((e) => GlobalKey()).toList();
    super.initState();
  }

  @override
  void dispose() {
    // ⭐ AP1-A3（审计 ✓）：原为空实现 ✗ → 监听与滚动控制器都被泄漏 ✓。
    // 注意 ✓：`_controller` 可能来自 `DefaultTabController.of(context)`（**宿主所有** ✓）
    // → **只能 removeListener，不能 dispose** ✗；`scrollController` 是本 State 自建 ✓ → 必须释放 ✓。
    _listenedAnimation?.removeListener(onTabChanged);
    scrollController.dispose();
    super.dispose();
  }

  PageStorageBucket get bucket => PageStorage.of(context);

  @override
  void didChangeDependencies() {
    _controller = widget.controller ?? DefaultTabController.of(context);
    initPainter();
    super.didChangeDependencies();
    var prevIndex = bucket.readState(context) as int?;
    if (prevIndex != null &&
        prevIndex != _controller.index &&
        prevIndex >= 0 &&
        prevIndex < widget.tabs.length) {
      _controller.index = prevIndex;
    }
    // ⭐ AP1-A3（审计 ✓）：订阅前先摘掉**旧**监听 ✓（防累积 ✗；行为不变 ✓ ——
    // `onTabChanged` 内部对同一 index 会提前 return ✓）
    _listenedAnimation?.removeListener(onTabChanged);
    _listenedAnimation = _controller.animation;
    _controller.animation!.addListener(onTabChanged);
  }

  @override
  void didUpdateWidget(covariant AppTabBar oldWidget) {
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? DefaultTabController.of(context);
      // ⭐ AP1-A3（审计 ✓）：订阅前先摘掉**旧**监听 ✓（防累积 ✗；行为不变 ✓ ——
      // `onTabChanged` 内部对同一 index 会提前 return ✓）
      _listenedAnimation?.removeListener(onTabChanged);
      _listenedAnimation = _controller.animation;
      _controller.animation!.addListener(onTabChanged);
      initPainter();
    }
    super.didUpdateWidget(oldWidget);
  }

  void initPainter() {
    var old = painter;
    painter = _IndicatorPainter(
      controller: _controller,
      // ⭐ F1-②：选中 tab 的**指示器填充**走「标签颜色」统一入口 ✓ ——
      // 原先写死 `colorScheme.primary` ✗ → 无论设置如何都是主题色 ✗
      // （用户实测：图片收藏「标签/作者/漫画」不随「标签颜色」变化 ✓）。
      // 跟随遮罩 → `windowOverlayColor()` ✓；跟随主题 → `secondaryContainer` ✓。
      // ⭐ Z1（用户澄清 ✓）：顶栏「漫画源」标签（含「+ 添加」✓）跟随**主题自己那套
      // tag/按钮色** ✓ = M3 的 **`secondaryContainer`** ✓（本项目最初"跟随主题"的标签/按钮
      // 就是用的它 ✓）。**不跟随自定义按钮色** ✗（`buttonOverlayColor` 那套 ✗），
      // 也不是 `primaryContainer` ✗（用户表述澄清 ✓）。
      // ⭐ AE1（用户要求 ✓）：**指示条**颜色改为"主题色但**更浅一档**" ✓ ——
      // 原先与 chip 底色同为 `secondaryContainer` ✗ → 完全看不见 ✗（用户实测 ✓）。
      // ⭐ AF1（用户要求 ✓）：指示条颜色 = **上面按钮色加深一档** ✓（保证对比度 ✓，
      // 不再与 chip 同色而看不见 ✗）。用 `AppOpacity.selectedTint` **令牌** ✓ 做黑混 ✓。
      color: Color.alphaBlend(
        Colors.black.withValues(alpha: AppOpacity.selectedTint),
        sourceTabOverlayColor(),
      ),
      // ⭐ B2 修复（审计 AP1-B2 ✓）：指示条**必须与可见 chip 用同一份内边距** ✗→✓ ——
      // 原先用 `tabPadding`（左右各 12 ✓）而 chip 实际是 `tabItemPadding`（左右各 7 ✓）
      // → 条比按钮**每侧短 5px** ✗ = 用户反复反馈的"没贴边 / 两端不对"的**真根因** ✓。
      // 该字段同时决定 `indicatorRect` 的左右范围与 `paint` 里裁切矩形的范围 ✓ → 同源即一致 ✓。
      padding: tabItemPadding,
      radius: windowOverlayBorderRadius()?.topLeft.x ?? tabRadius,
    );
    if (old != null && old.offsets != null && old.itemHeight != null) {
      painter!.update(old.offsets!, old.itemHeight!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller.animation ?? _controller,
      builder: buildTabBar,
    );
  }

  void _tabLayoutCallback(List<double> offsets, double itemHeight) {
    painter!.update(offsets, itemHeight);
    this.offsets = offsets;
  }

  Widget buildTabBar(BuildContext context, Widget? _) {
    var child = SmoothScrollProvider(
      controller: scrollController,
      builder: (context, controller, physics) {
        return SingleChildScrollView(
          key: const PageStorageKey('scroll'),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          controller: controller,
          physics: physics is BouncingScrollPhysics
              ? const ClampingScrollPhysics()
              : physics,
          child: CustomPaint(
            // ⭐ AE1（用户实测 ✓）：指示条原先用 `painter:` ✗ → **画在子控件之下** ✗，
            // 被 chip 自身的 `Material` 底色盖住 ✗（用户："这个条被覆盖了" ✓）。
            // 改用 `foregroundPainter:` ✓ → 画在 chip **之上** ✓ = "显示在选中的按钮上" ✓。
            foregroundPainter: painter,
            child: _TabRow(
              callback: _tabLayoutCallback,
              children: List.generate(widget.tabs.length, buildTab)
                ..addIfNotNull(
                  widget.actionButton?.padding(
                    // ⭐ AC1（用户要求 ✓）：**间距统一** ✓ —— 加号与 chip 用**同一个**间距常量 ✓
                    //（此前是 `EdgeInsets.all(AppSpace.xs)`=4 ✗，与 chip 的 7 不一致 ✗）。
                    // 方形由 `TabActionButton` 内的 36×36 紧约束保证 ✓，此处只管间距 ✓。
                    _AppTabBarState.tabItemPadding,
                  ),
                ),
            ),
          ).paddingHorizontal(4),
        );
      },
    );
    return Container(
      key: tabBarKey,
      // 自适应：最小高度 + 随文字（字号缩放）撑开，默认字号外观不变
      constraints: const BoxConstraints(minHeight: _kTabHeight),
      width: double.infinity,
      // ⭐ AD1（用户实测 ✓）：**分割线离按钮再远 4px** ✓ —— 底部内边距把下边框向下推 ✓
      //（原先线与 chip 贴太近 ✗ "显得有点拥挤" ✗）。用令牌 `AppSpace.xs` ✓ 不写数字 ✗。
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      decoration: widget.withUnderLine
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            )
          : null,
      child: widget.tabs.isEmpty ? const SizedBox() : child,
    );
  }

  int? previousIndex;

  void onTabChanged() {
    final int i = _controller.index;
    if (i == previousIndex) {
      return;
    }
    updateScrollOffset(i);
    previousIndex = i;
    bucket.writeState(context, i);
  }

  void updateScrollOffset(int i) {
    // try to scroll to center the tab
    final RenderBox tabBarBox =
        tabBarKey.currentContext!.findRenderObject() as RenderBox;
    final double tabLeft = offsets[i];
    final double tabRight = offsets[i + 1];
    final double tabWidth = tabRight - tabLeft;
    final double tabCenter = tabLeft + tabWidth / 2;
    final double tabBarWidth = tabBarBox.size.width;
    double scrollOffset = tabCenter - tabBarWidth / 2;
    if (scrollOffset == scrollController.offset) {
      return;
    }
    scrollOffset = scrollOffset.clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.animateTo(
      scrollOffset,
      duration: AppMotion.short,
      curve: Curves.easeInOut,
    );
  }

  void onTabClicked(int i) {
    _controller.animateTo(i);
  }

  Widget buildTab(int i) {
    // 启用「窗口/按钮背景」时，圆角跟随「圆角样式」设置。
    final radius = appdata.settings.customBackgroundActive
        ? (windowOverlayBorderRadius() ?? BorderRadius.circular(tabRadius))
        : BorderRadius.circular(tabRadius);
    final tab = InkWell(
      onTap: () => onTabClicked(i),
      borderRadius: radius,
      child: KeyedSubtree(
        key: keys[i],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(
              // ⭐ 对比度（2026-10-11 ✓）：**未选中的标签**取 col 之前会固定用 `colorScheme.onSurface` ✗
              // ⇒ 深色主题下它是**浅色（近白）** ✗，而本 chip 底色可由「漫画源颜色」设为**浅色** ✓
              // ⇒ 浅底叠浅字、看不见 ✗（用户实测：这一排未选中项文字消失 ✓）。
              // ⇒ 现在按**本 chip 实际填充色**的深浅自动配黑/白 ✓；用户**手动设了文字颜色**则优先跟随用户 ✓。
              color: i == _controller.animation?.value.round()
                  ? context.colorScheme.primary
                  : (globalTextColor() ??
                        onColorForFill(context, sourceTabOverlayColor())),
              fontWeight: FontWeight.w500,
              // 启用「窗口/按钮背景」时把标签文字调大一点。
              fontSize: appdata.settings.customBackgroundActive ? 14 : null,
            ),
            child: widget.tabs[i],
          ),
        ),
      ),
    );
    // 启用「窗口/按钮背景」时，遮罩挂在 InkWell 上 —— 与鼠标悬停高亮**同一尺寸**。
    // 同时整体上移 5px（上 1 / 下 11）。
    if (appdata.settings.customBackgroundActive) {
      return Material(
        // F1-②：tab 底同样走统一入口 ✓（原先恒 `windowOverlayColor()` ✗ → 不随设置变化 ✓）
        // ⭐ Z1（用户选定 A ✓）：顶栏「漫画源」标签（含「+ 添加」✓）**跟随主题色本身** ✓，
        // **不再跟随标签颜色** ✗（用户实测反馈 ✓：这一排应跟主题 ✓，不跟标签/胶囊按钮色 ✗）。
        // 用 `primaryContainer` ✓ —— 它由**种子色**直接派生 ✓（当前种子青色 → 青色系 ✓），
        // 且与胶囊按钮用的 `secondaryFixed` 是**两套**色 ✓（互不牵连 ✓）。
        // ⭐ AF1（用户要求 ✓）：填色走**新统一入口** `sourceTabOverlayColor()` ✓ ——
        // `system` = 跟随主题（`secondaryContainer` ✓ 零回归）/ `transparent` / `#RRGGBB` × 不透明度 ✓。
        color: sourceTabOverlayColor(),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        // ⭐ AA1（用户要求 ✓）：**可见 chip 的间距/高度由这里决定** ✗（上面的 `tabPadding`
        // 在这条"自定义背景"分支**被覆盖** ✗ —— 这就是"改了 tabPadding 却看不到变化"✗ 的真因 ✓）。
        // 用户实测要求 ✓：左右间距各 +5px、按钮高度 −4px → `left/right: 2 → 7` ✓、`bottom: 11 → 7` ✓。
        // ⭐ AA1（用户实测 ✓）：左右间距 +5px ✓；高度收窄 ✓（"太厚了" ✗）——
        // 与「+ 加号按钮」**共用** `tabItemPadding` ✓，保证两者厚度/间距一致 ✓。
        child: tab,
      ).padding(tabItemPadding);
    }
    return tab.padding(tabPadding);
  }
}

typedef _TabRenderCallback =
    void Function(List<double> offsets, double itemHeight);

class _TabRow extends Row {
  const _TabRow({required this.callback, required super.children});

  final _TabRenderCallback callback;

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _RenderTabFlex(
      direction: Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      textDirection: Directionality.of(context),
      verticalDirection: VerticalDirection.down,
      callback: callback,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderTabFlex renderObject) {
    super.updateRenderObject(context, renderObject);
    renderObject.callback = callback;
  }
}

class _RenderTabFlex extends RenderFlex {
  _RenderTabFlex({
    required super.direction,
    required super.mainAxisSize,
    required super.mainAxisAlignment,
    required super.crossAxisAlignment,
    required TextDirection super.textDirection,
    required super.verticalDirection,
    required this.callback,
  });

  _TabRenderCallback callback;

  @override
  void performLayout() {
    super.performLayout();
    RenderBox? child = firstChild;
    final List<double> xOffsets = <double>[];
    while (child != null) {
      final FlexParentData childParentData =
          child.parentData! as FlexParentData;
      xOffsets.add(childParentData.offset.dx);
      assert(child.parentData == childParentData);
      child = childParentData.nextSibling;
    }
    xOffsets.add(size.width);
    callback(xOffsets, firstChild!.size.height);
  }
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.color,
    required this.padding,
    this.radius = 4.0,
  }) : super(repaint: controller.animation);

  final TabController controller;
  final Color color;
  final EdgeInsets padding;
  final double radius;

  List<double>? offsets;
  double? itemHeight;
  Rect? _currentRect;

  void update(List<double> offsets, double itemHeight) {
    this.offsets = offsets;
    this.itemHeight = itemHeight;
  }

  int get maxTabIndex => offsets!.length - 2;

  /// ⭐ AI1 续3：按钮的**可见底边** = 行高（实测 `itemHeight` ✓）− chip 自身的下内边距 ✓
  ///（`tabItemPadding.bottom` ✓）。提到 painter 级别 ✓ → `indicatorRect` 与 `paint` 的裁切
  /// **同源** ✓（避免再次出现"条被裁掉"✗ / "条跑到按钮外"✗）。
  double get pillBottom =>
      (itemHeight ?? _AppTabBarState._kTabHeight) -
      _AppTabBarState.tabItemPadding.bottom;

  Rect indicatorRect(Size tabBarSize, int tabIndex) {
    assert(offsets != null);
    assert(offsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    var (tabLeft, tabRight) = (offsets![tabIndex], offsets![tabIndex + 1]);

    // ⭐ AI1 续3（用户反馈 ✓）：条必须**在按钮内部**且**覆盖整个底边** ✓ ——
    // 关键：按钮的**可见底边** = 行高（实测 `itemHeight` ✓）**减去 chip 自身的下内边距** ✓
    //（`tabItemPadding.bottom` ✓，**同源** ✓）。此前直接用 `itemHeight` ✗ → 条落到按钮**外面**
    // 接了一块 ✗（用户："变成给按钮接一块了"✗）；直接用固定高度 ✗ 又会浮在上方留缝 ✗。
    // ⭐ AJ1 续（用户反馈"没变化"✓）：胶囊两端要**看得出半圆** ✓ —— 必须让两端落在按钮的
    // **直边范围**内 ✓，否则会被按钮自身圆角裁成斜口 ✗（这就是"没变化"✓ 的真相 ✗）。
    // 内缩量取**按钮圆角半径**（`radius` ✓，随「圆角样式」设置变化 ✓）= 两端正好躲开圆角 ✓。
    final double endInset = radius;
    var rect = Rect.fromLTWH(
      tabLeft + padding.left + endInset,
      pillBottom - 3,
      tabRight - tabLeft - padding.horizontal - endInset * 2,
      3,
    );

    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (offsets == null || itemHeight == null) {
      return;
    }
    // ⭐ AH1（用户反馈 ✓）：**修动画方向 bug** —— 原先直接把 `controller.animation.value`
    // 当进度 ✗，而它的**方向随切换方向变** ✗：往后切时是 `1 → 0` ✗ → 条反而"缩回去"✗
    //（用户实测："第一个按钮动画是**反的（消失）**"✗）。改为按**到目标索引的距离**归一化 ✓：
    // 停稳时 = 1 ✓（条满高 ✓）；切换过程中 = 0 → 1 ✓ → **无论方向都播一次"由底浮现"** ✓
    //（"每次切换必播"✓，不再有反向 ✗ / 僵硬闪现 ✗）。
    final double raw = controller.animation!.value;
    final double t = (1 - (raw - controller.index).abs()).clamp(0.0, 1.0);
    final double eased = Curves.easeOutCubic.transform(t);
    final Rect target = indicatorRect(size, controller.index);
    final double h = target.height * eased;
    _currentRect = Rect.fromLTWH(
      target.left,
      target.bottom - h,
      target.width,
      h,
    );
    final Paint paint = Paint()..color = color;
    // ⭐ AI1（用户要求 ✓）：**直角** ✓（"这个线不要做圆角了"✓）—— 条本体画直角矩形 ✓；
    // **不出框** ✓ 由**按按钮自身形状裁切**保证 ✓：圆角样式 → 裁成圆角 ✓；
    // 切成直角样式 → 裁成直角 ✓（"包括圆角和切换成直角的边缘"✓）。
    final double chipLeft = offsets![controller.index] + padding.left;
    final double chipRight = offsets![controller.index + 1] - padding.left;
    final Rect chipRect = Rect.fromLTWH(
      chipLeft,
      0,
      (chipRight - chipLeft).clamp(0, size.width),
      // ⭐ AI1 续3：裁切高度**与条同源** ✓ —— 同样减去 chip 的下内边距 ✓
      //（此前两者不一致 ✗ 导致"条被裁掉"✗ 或"条跑到按钮外"✗）。
      pillBottom,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(chipRect, Radius.circular(radius)),
    );
    // ⭐ AJ1（用户要求 ✓）：条改为**两侧半圆的细长胶囊** ✓ —— 圆角半径取 **高度的一半** ✓
    //（`height / 2` ✓ → 两端正好是半圆 ✓）；位置与尺寸**保持不变** ✓（用户明确要求 ✓）。
    // 外层仍按按钮形状 `clipRRect` 裁切 ✓ → 依旧**不出框** ✓。
    final RRect capsule = RRect.fromRectAndRadius(
      _currentRect!,
      Radius.circular(_currentRect!.height / 2),
    );
    canvas.drawRRect(capsule, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // ⭐ AF1（修 bug ✓）：返回 true ✓ —— 此前为 false ✗，`update(offsets, itemHeight)`
    // 更新布局数据后**不触发重绘** ✗（用户反馈"现在的动画有 bug"✗ 的原因之一 ✓）。
    return true;
  }
}

class TabViewBody extends StatefulWidget {
  /// Create a tab view body, which will show the child at the current tab index.
  const TabViewBody({super.key, required this.children, this.controller});

  final List<Widget> children;

  final TabController? controller;

  @override
  State<TabViewBody> createState() => _TabViewBodyState();
}

class _TabViewBodyState extends State<TabViewBody> {
  late TabController _controller;

  int _currentIndex = 0;

  void updateIndex() {
    if (_controller.index != _currentIndex) {
      setState(() {
        _currentIndex = _controller.index;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = widget.controller ?? DefaultTabController.of(context);
    _currentIndex = _controller.index;
    _controller.addListener(updateIndex);
  }

  @override
  void dispose() {
    super.dispose();
    _controller.removeListener(updateIndex);
  }

  @override
  Widget build(BuildContext context) {
    return widget.children[_currentIndex];
  }
}

class SearchBarController {
  _SearchBarMixin? _state;

  final void Function(String text)? onSearch;

  String currentText;

  void setText(String text) {
    _state?.setText(text);
  }

  String get text => _state?.getText() ?? '';

  set text(String text) {
    setText(text);
  }

  SearchBarController({this.onSearch, this.currentText = ''});
}

abstract mixin class _SearchBarMixin {
  void setText(String text);

  String getText();
}

class SliverSearchBar extends StatefulWidget {
  const SliverSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.action,
    this.focusNode,
  });

  final SearchBarController controller;

  final void Function(String)? onChanged;

  final Widget? action;

  final FocusNode? focusNode;

  @override
  State<SliverSearchBar> createState() => _SliverSearchBarState();
}

class _SliverSearchBarState extends State<SliverSearchBar>
    with _SearchBarMixin {
  late TextEditingController _editingController;

  late SearchBarController _controller;

  @override
  void initState() {
    _controller = widget.controller;
    _controller._state = this;
    _editingController = TextEditingController(text: _controller.currentText);
    super.initState();
  }

  @override
  void setText(String text) {
    _editingController.text = text;
  }

  @override
  String getText() {
    return _editingController.text;
  }

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverSearchBarDelegate(
        editingController: _editingController,
        controller: _controller,
        topPadding: MediaQuery.of(context).padding.top,
        fontScale: _barTextScale(context),
        onChanged: widget.onChanged,
        action: widget.action,
        focusNode: widget.focusNode,
      ),
    );
  }

  @override
  void dispose() {
    // `_editingController` 由本 State 自建 ✓ → 必须释放 ✓；
    // `_controller`（SearchBarController）来自 `widget.controller`（宿主所有 ✗）→ 不释放 ✗。
    _editingController.dispose();
    super.dispose();
  }
}

class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController editingController;

  final SearchBarController controller;

  final double topPadding;

  /// ⭐ 本轮：顶栏高度用的缩放系数 ✓（与文字同源 ✓，见 `_barTextScale` ✓）——
  /// `minExtent`/`maxExtent` 是**无 context 的 getter** ✗，故由 [SliverSearchBar] 传入 ✓。
  final double fontScale;

  final void Function(String)? onChanged;

  final Widget? action;

  final FocusNode? focusNode;

  const _SliverSearchBarDelegate({
    required this.editingController,
    required this.controller,
    required this.topPadding,
    required this.fontScale,
    this.onChanged,
    this.action,
    this.focusNode,
  });

  static const _kAppBarHeight = 52.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      // ⭐ 本轮：内部下限与 `maxExtent`/`minExtent` **同源同系数** ✓ —— 若此处仍按
      // 未缩放值算 ✗，app 内缩放小于 1 时它会顶住 sliver 给的高度 ⇒ 溢出 ✗。
      constraints: BoxConstraints(
        minHeight: (_kAppBarHeight + topPadding) * fontScale,
      ),
      width: double.infinity,
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: customBackgroundAware(Theme.of(context).colorScheme.surface),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const BackButton(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: TextField(
                focusNode: focusNode,
                controller: editingController,
                decoration: InputDecoration(
                  hintText: "Search".tl,
                  border: InputBorder.none,
                ),
                onSubmitted: (text) {
                  controller.onSearch?.call(text);
                },
                onChanged: onChanged,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: editingController,
            builder: (context, child) {
              return editingController.text.isEmpty
                  ? const SizedBox()
                  : IconButton(
                      iconSize: AppIconSize.md,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        editingController.clear();
                        onChanged?.call("");
                      },
                    );
            },
          ),
          if (action != null) action!,
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  double get maxExtent => (_kAppBarHeight + topPadding) * fontScale;

  @override
  double get minExtent => (_kAppBarHeight + topPadding) * fontScale;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _SliverSearchBarDelegate ||
        editingController != oldDelegate.editingController ||
        controller != oldDelegate.controller ||
        topPadding != oldDelegate.topPadding ||
        fontScale != oldDelegate.fontScale;
  }
}

class AppSearchBar extends StatefulWidget {
  const AppSearchBar({super.key, required this.controller, this.action});

  final SearchBarController controller;

  final Widget? action;

  @override
  State<AppSearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<AppSearchBar> with _SearchBarMixin {
  late TextEditingController _editingController;

  late SearchBarController _controller;

  @override
  void setText(String text) {
    _editingController.text = text;
  }

  @override
  String getText() {
    return _editingController.text;
  }

  @override
  void initState() {
    _controller = widget.controller;
    _controller._state = this;
    _editingController = TextEditingController(text: _controller.currentText);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      constraints: BoxConstraints(minHeight: _kAppBarHeight + topPadding),
      width: double.infinity,
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const BackButton(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: TextField(
                controller: _editingController,
                decoration: InputDecoration(
                  hintText: "Search".tl,
                  border: InputBorder.none,
                ),
                onSubmitted: (text) {
                  _controller.onSearch?.call(text);
                },
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _editingController,
            builder: (context, child) {
              return _editingController.text.isEmpty
                  ? const SizedBox()
                  : IconButton(
                      iconSize: AppIconSize.md,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _editingController.clear();
                      },
                    );
            },
          ),
          if (widget.action != null) widget.action!,
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // `_editingController` 由本 State 自建 ✓ → 必须释放 ✓；
    // `_controller`（SearchBarController）来自 `widget.controller`（宿主所有 ✗）→ 不释放 ✗。
    _editingController.dispose();
    super.dispose();
  }
}

class TabActionButton extends StatelessWidget {
  const TabActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final Icon icon;

  final void Function() onPressed;

  @override
  Widget build(BuildContext context) {
    // 启用「窗口/按钮背景」时，与标签一样带圆角底色（圆角跟随设置）。
    final radius = appdata.settings.customBackgroundActive
        ? (windowOverlayBorderRadius() ?? BorderRadius.circular(AppRadius.md))
        : BorderRadius.circular(AppRadius.md);
    final content = InkWell(
      onTap: onPressed,
      borderRadius: radius,
      child: Container(
        // ⭐ AC1（用户要求 ✓）：加号按钮做成 **36×36 正方形** ✓ —— 边长用与 chip 同一个令牌 ✓
        //（`AppTopBar.tabHeight` ✓，不写数字 ✗）；`alignment: center` 让图标居中、四边等距 ✓。
        alignment: Alignment.center,
        constraints: BoxConstraints.tightFor(
          width: AppTopBar.tabHeight,
          height: AppTopBar.tabHeight,
        ),
        child: IconTheme(
          data: IconThemeData(
            // ⭐ AA1（用户要求 ✓）：**纯图标按钮** ✓ —— 去掉「添加」文字 ✗、图标**更大** ✓；
            // 颜色**跟随本排主题色** ✓（`onSecondaryContainer` 配 `secondaryContainer` ✓），
            // **不再跟随「图标按钮」的自定义色** ✗（原先走 `appIconColor()` ✗，用户实测指出 ✓）。
            size: AppIconSize.lg,
            color: context.colorScheme.onSecondaryContainer,
          ),
          child: icon, // 只留图标 ✓（真正的图标按钮 ✓）
        ),
      ),
    );
    if (appdata.settings.customBackgroundActive) {
      return Material(
        // ⭐ I1：顶栏「动作按钮」（图标按钮，如设置/排序/搜索/⋯ ✓）底色走**按钮独立入口** ✓
        //（原先 `windowOverlayColor()` ✗ → 与顶栏面板同色、不受「按钮背景」设置控制 ✗，
        //  用户实测反馈"只有图标的按钮都不受控" ✓）。
        // ⭐ AA1（用户要求 ✓）：填色与本排标签一致（主题 `secondaryContainer` ✓），
        // **不再跟随「图标按钮」的自定义色** ✗（原先 `iconOverlayColor()` ✗，用户实测指出 ✓）。
        // ⭐ AF1（用户要求 ✓）：「+ 加号」与 chip 用**同一个**入口 ✓（同属这一排 ✓）。
        color: sourceTabOverlayColor(),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return content;
  }
}
