part of "components.dart";

void showMenuX(BuildContext context, Offset location, List<MenuEntry> entries) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(_MenuRoute(entries, location));
}

class _MenuRoute<T> extends PopupRoute<T> {
  final List<MenuEntry> entries;

  final Offset location;

  _MenuRoute(this.entries, this.location);

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => "menu";

  double get entryHeight => App.isMobile ? 42 : 36;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // 建立设置依赖：菜单表面的遮罩色/圆角由设置算出 → 变化时需重建
    // （本方法是路由的 buildPage，没有自己的 widget 元素；依赖注册在传入的
    //  context 所属元素上，菜单本身是瞬时弹层，影响面最小但语义正确 ✓）
    AppSettingsScope.of(context);
    var width = entries.first.icon == null ? 216.0 : 242.0;
    final size = MediaQuery.of(context).size;
    var left = location.dx;
    if (left < 10) {
      left = 10;
    }
    if (left + width > size.width - 10) {
      left = size.width - width - 10;
    }
    var top = location.dy;
    var height = 16 + entryHeight * entries.length;
    if (top + height > size.height - 15) {
      top = size.height - height - 15;
    }
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Container(
            decoration: BoxDecoration(
              borderRadius:
                  windowOverlayBorderRadius() ??
                  BorderRadius.circular(AppRadius.sm),
              border: context.brightness == Brightness.dark
                  ? Border.all(color: context.colorScheme.outlineVariant)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: context.colorScheme.shadow.toOpacity(0.2),
                  blurRadius: 8,
                  blurStyle: BlurStyle.outer,
                ),
              ],
            ),
            child: BlurEffect(
              borderRadius:
                  windowOverlayBorderRadius() ??
                  BorderRadius.circular(AppRadius.sm),
              child: Material(
                // ⭐ AQ1(2/3)（用户要求 ✓，2026-10-09）：菜单底色改走**独立统一入口** ✓ ——
                // 原先写 `customBackgroundActive ? windowOverlayColor() : <主题表面色 · 92% 不透明>` ✗，
                // 而 `customBackgroundActive` **恒真** ✗（见 `appdata.dart` 的 `cornerStyleActive` ✓
                // 与 `secondaryPageFeatureActive` 默认 opaque ✓）→ **恒取窗口遮罩色** ✓，
                // 在"窗口遮罩 = 透明"的设置下菜单就是**全透明** ✗ → 用户反馈"**可视化非常差**"✗。
                // 现走 `menuSurfaceColor()` ✓：`system`（默认 ✓）= **跟随主题的表面色** ✓
                // × 0.92 不透明度 ✓ → 开箱即可读 ✓；并可在「外观 → 弹出式二级页面」里
                // 自行改底色 / 不透明度 ✓（与既有二级页面外观项同构 ✓，保留设计理念 ✓）。
                color: menuSurfaceColor(),
                borderRadius:
                    windowOverlayBorderRadius() ??
                    BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: width,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpace.md,
                    horizontal: AppSpace.tiny,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: entries
                        .map((e) => buildEntry(e, context))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildEntry(MenuEntry entry, BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {
        Navigator.of(context).pop();
        entry.onClick();
      },
      child: SizedBox(
        height: entryHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Row(
            children: [
              if (entry.icon != null)
                Icon(entry.icon, size: AppIconSize.sm, color: entry.color),
              const SizedBox(width: 12),
              Text(entry.text, style: TextStyle(color: entry.color)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Duration get transitionDuration => AppMotion.short;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(
        Tween<double>(begin: 0, end: 1).chain(CurveTween(curve: Curves.ease)),
      ),
      child: child,
    );
  }
}

class MenuEntry {
  final String text;
  final IconData? icon;
  final Color? color;
  final void Function() onClick;

  MenuEntry({required this.text, this.icon, this.color, required this.onClick});
}
