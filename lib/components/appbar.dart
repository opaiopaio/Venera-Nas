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
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.tiny,
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
/// 未启用背景时退回主题表面色，保证顶栏**始终不透明**。
/// 只有 `blur` 样式且未启用背景时才保留原来的毛玻璃观感。
Widget _headerSurface(BuildContext context, AppbarStyle style, Widget body) {
  Widget surface = _HeaderSurface(body: body);
  if (style == AppbarStyle.blur && !AppBackground.isActive) {
    surface = BlurEffect(blur: 15, child: surface);
  }
  return surface;
}

class _HeaderSurface extends StatefulWidget {
  const _HeaderSurface({required this.body});

  final Widget body;

  @override
  State<_HeaderSurface> createState() => _HeaderSurfaceState();
}

class _HeaderSurfaceState extends State<_HeaderSurface> {
  /// 顶栏左上角在窗口坐标里的位置。首帧未知 → 先只画不透明兜底，下一帧补背景。
  Offset? _offsetInWindow;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final offset = box.localToGlobal(Offset.zero);
      if (offset != _offsetInWindow) {
        setState(() => _offsetInWindow = offset);
      }
    });
    final offset = _offsetInWindow;
    return ClipRect(
      child: Stack(
        // body 必须**撑满**顶栏（StackFit.expand）→ Row 的 crossAxisAlignment=center
        // 才能在纵向居中；否则非定位子项按顶部对齐，标题/按钮会贴着顶栏上沿。
        fit: StackFit.expand,
        children: [
          // 不透明兜底（背景底色可能是半透明的）
          Positioned.fill(
            child: ColoredBox(color: context.colorScheme.surface),
          ),
          if (AppBackground.isActive && offset != null)
            Positioned(
              left: -offset.dx,
              top: -offset.dy,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: const AppBackground(),
              ),
            ),
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
        radius: radius,
        style: style,
      ),
    );
  }
}

const _kAppBarHeight = 52.0;

class _MySliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget? leading;

  final Widget title;

  final List<Widget>? actions;

  final double topPadding;

  final double radius;

  final AppbarStyle style;

  _MySliverAppBarDelegate({
    this.leading,
    required this.title,
    this.actions,
    required this.topPadding,
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
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.tiny,
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
  double get maxExtent =>
      (_kAppBarHeight + topPadding) * globalFontScale().clamp(1.0, 1.4);

  @override
  double get minExtent =>
      (_kAppBarHeight + topPadding) * globalFontScale().clamp(1.0, 1.4);

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _MySliverAppBarDelegate ||
        leading != oldDelegate.leading ||
        title != oldDelegate.title ||
        actions != oldDelegate.actions ||
        topPadding != oldDelegate.topPadding ||
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

  static const _kTabHeight = 48.0;

  static const tabPadding = EdgeInsets.symmetric(
    horizontal: AppSpace.xxs,
    vertical: AppSpace.tiny,
  );

  static const tabRadius = 8.0;

  _IndicatorPainter? painter;

  var scrollController = ScrollController();

  var tabBarKey = GlobalKey();

  var offsets = <double>[];

  @override
  void initState() {
    keys = widget.tabs.map((e) => GlobalKey()).toList();
    super.initState();
  }

  @override
  void dispose() {
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
    _controller.animation!.addListener(onTabChanged);
  }

  @override
  void didUpdateWidget(covariant AppTabBar oldWidget) {
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? DefaultTabController.of(context);
      _controller.animation!.addListener(onTabChanged);
      initPainter();
    }
    super.didUpdateWidget(oldWidget);
  }

  void initPainter() {
    var old = painter;
    painter = _IndicatorPainter(
      controller: _controller,
      color: context.colorScheme.primary,
      padding: tabPadding,
      radius: tabRadius,
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
            painter: painter,
            child: _TabRow(
              callback: _tabLayoutCallback,
              children: List.generate(widget.tabs.length, buildTab)
                ..addIfNotNull(
                  widget.actionButton?.padding(
                    // 与标签用同样的内边距，保证「添加」按钮与标签对齐。
                    appdata.settings.customBackgroundActive
                        ? const EdgeInsets.only(
                            left: 2,
                            right: 2,
                            top: 1,
                            bottom: 11,
                          )
                        : tabPadding,
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
              color: i == _controller.animation?.value.round()
                  ? context.colorScheme.primary
                  : context.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
              // 启用「窗口/按钮背景」时把标签文字调大一点。
              fontSize: appdata.settings.customBackgroundActive ? 16 : null,
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
        color: windowOverlayColor(),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: tab,
      ).padding(const EdgeInsets.only(left: 2, right: 2, top: 1, bottom: 11));
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

  Rect indicatorRect(Size tabBarSize, int tabIndex) {
    assert(offsets != null);
    assert(offsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    var (tabLeft, tabRight) = (offsets![tabIndex], offsets![tabIndex + 1]);

    const horizontalPadding = 12.0;

    var rect = Rect.fromLTWH(
      tabLeft + padding.left + horizontalPadding,
      _AppTabBarState._kTabHeight - 3.6,
      tabRight - tabLeft - padding.horizontal - horizontalPadding * 2,
      3,
    );

    return rect;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (offsets == null || itemHeight == null) {
      return;
    }
    final double index = controller.index.toDouble();
    final double value = controller.animation!.value;
    final bool ltr = index > value;
    final int from = (ltr ? value.floor() : value.ceil()).clamp(0, maxTabIndex);
    final int to = (ltr ? from + 1 : from - 1).clamp(0, maxTabIndex);
    final Rect fromRect = indicatorRect(size, from);
    final Rect toRect = indicatorRect(size, to);
    _currentRect = Rect.lerp(fromRect, toRect, (value - from).abs());
    final Paint paint = Paint()..color = color;
    final RRect rrect = RRect.fromRectAndCorners(
      _currentRect!,
      topLeft: Radius.circular(radius),
      topRight: Radius.circular(radius),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
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
        onChanged: widget.onChanged,
        action: widget.action,
        focusNode: widget.focusNode,
      ),
    );
  }
}

class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController editingController;

  final SearchBarController controller;

  final double topPadding;

  final void Function(String)? onChanged;

  final Widget? action;

  final FocusNode? focusNode;

  const _SliverSearchBarDelegate({
    required this.editingController,
    required this.controller,
    required this.topPadding,
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
      constraints: BoxConstraints(minHeight: _kAppBarHeight + topPadding),
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
  double get maxExtent =>
      (_kAppBarHeight + topPadding) * globalFontScale().clamp(1.0, 1.4);

  @override
  double get minExtent =>
      (_kAppBarHeight + topPadding) * globalFontScale().clamp(1.0, 1.4);

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate is! _SliverSearchBarDelegate ||
        editingController != oldDelegate.editingController ||
        controller != oldDelegate.controller ||
        topPadding != oldDelegate.topPadding;
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
}

class TabActionButton extends StatelessWidget {
  const TabActionButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  final Icon icon;

  final String text;

  final void Function() onPressed;

  static const _kTabHeight = 46.0;

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
        constraints: const BoxConstraints(minHeight: _kTabHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        child: IconTheme(
          data: IconThemeData(
            size: AppIconSize.md,
            color: context.colorScheme.primary,
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Text(text, style: ts.withColor(context.colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
    if (appdata.settings.customBackgroundActive) {
      return Material(
        color: windowOverlayColor(),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return content;
  }
}
