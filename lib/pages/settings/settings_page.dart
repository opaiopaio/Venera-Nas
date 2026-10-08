import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/components/pin_pad.dart';
import 'package:venera_nas/foundation/app.dart';
// ⭐ AV1（2026-10-09）：外观四个子页要复用 App 自己的**横向切入**转场
//（`SlidePageTransitionBuilder` ✓，见 `foundation/app_page_route.dart` ✓）→ 补本导入 ✓。
import 'package:venera_nas/foundation/app_page_route.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/favorites.dart';
import 'package:venera_nas/foundation/history.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/app_dio.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';
import 'package:venera_nas/utils/auth_storage.dart';
import 'package:venera_nas/utils/data.dart';
import 'package:venera_nas/utils/data_sync.dart';
import 'package:venera_nas/utils/comic_backup.dart';
import 'package:venera_nas/utils/io.dart';
import 'package:venera_nas/utils/translations.dart';
import 'package:yaml/yaml.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/app_theme.dart';

part 'reader.dart';
part 'explore_settings.dart';
part 'setting_components.dart';
part 'appearance.dart';
part 'appearance_background_page.dart';
part 'appearance_window_page.dart';
part 'appearance_secondary_page.dart';
part 'appearance_text_page.dart';
part 'local_favorites.dart';
part 'app.dart';
part 'auth_pin_setting.dart';
part 'about.dart';
part 'network.dart';
part 'debug.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage = -1, super.key});

  final int initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int currentPage = -1;

  ColorScheme get colors => Theme.of(context).colorScheme;

  bool get enableTwoViews => context.width > 720;

  final categories = <String>[
    "Explore",
    "Reading",
    "Appearance",
    "Local Favorites",
    "APP",
    "Network",
    "About",
    "Debug",
  ];

  final icons = <IconData>[
    Icons.explore,
    Icons.book,
    Icons.color_lens,
    Icons.collections_bookmark_rounded,
    Icons.apps,
    Icons.public,
    Icons.info,
    Icons.bug_report,
  ];

  @override
  void initState() {
    currentPage = widget.initialPage;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：本控件的外观由设置算出 → 设置变化时由框架精准重建
    // （见 doc-private/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    return Material(color: customBackgroundAware(null), child: buildBody());
  }

  Widget buildBody() {
    if (enableTwoViews) {
      return Row(
        children: [
          SizedBox(width: 280, height: double.infinity, child: buildLeft()),
          Container(
            height: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: context.colorScheme.outlineVariant,
                  width: 0.6,
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              transitionBuilder: (child, animation) {
                return LayoutBuilder(
                  builder: (context, constrains) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        var width = constrains.maxWidth;
                        var value = animation.isForwardOrCompleted
                            ? 1 - animation.value
                            : 1;
                        var left = width * value;
                        return Stack(
                          children: [
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: width,
                              child: child,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
              child: buildRight(),
            ),
          ),
        ],
      );
    } else {
      return buildLeft();
    }
  }

  Widget buildLeft() {
    return Material(
      color: customBackgroundAware(null),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Tooltip(
                  message: "Back",
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: context.pop,
                  ),
                ),
                const SizedBox(width: 24),
                Text("Settings".tl, style: ts.s20),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: buildCategories()),
        ],
      ),
    );
  }

  Widget buildCategories() {
    Widget buildItem(String name, int id) {
      final bool selected = id == currentPage;

      Widget content = AnimatedContainer(
        key: ValueKey(id),
        duration: AppMotion.short,
        width: double.infinity,
        height: 46,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer.toOpacity(0.36)
              : windowOverlayColor(),
          // 配置了「窗口/按钮背景」时，左栏菜单项也用圆角方框（与侧栏一致）。
          borderRadius: appdata.settings.cornerStyleActive
              ? BorderRadius.circular(windowOverlayRadius())
              : null,
          border: Border(
            left: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icons[id]),
            const SizedBox(width: 16),
            Text(name, style: ts.s16),
            const Spacer(),
            if (selected) const Icon(Icons.arrow_right),
          ],
        ),
      );

      return Padding(
        padding: enableTwoViews
            ? const EdgeInsets.fromLTRB(8, 0, 8, 0)
            : EdgeInsets.zero,
        child: InkWell(
          borderRadius: appdata.settings.cornerStyleActive
              ? BorderRadius.circular(windowOverlayRadius())
              : null,
          onTap: () {
            if (enableTwoViews) {
              setState(() => currentPage = id);
            } else {
              context.to(() => _SettingsDetailPage(pageIndex: id));
            }
          },
          child: content,
        ).paddingVertical(4),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length,
      itemBuilder: (context, index) => buildItem(categories[index].tl, index),
    );
  }

  Widget buildRight() {
    if (currentPage == -1) {
      return const SizedBox();
    }
    return Navigator(
      // ⭐ AO1 续（用户实测 ✓）：**必须给内层 Navigator 一个随 `currentPage` 变化的 key** ✓ ——
      // 否则 `onGenerateRoute` 只对**新路由**生效 ✗ → 切换设置项后**旧路由仍显示** ✗
      //（用户实测："左侧可点，但右侧页面不刷新"✗；直到 pop 掉子页才露出新页 ✓）。
      // 加 key 后：切换设置项 → Navigator **重建** ✓ → 立即显示所点页面 ✓（子页也随之丢弃 ✓）。
      key: ValueKey(currentPage),
      onGenerateRoute: (settings) {
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return _buildSettingsContent(currentPage);
          },
          transitionDuration: Duration.zero,
          // ⭐ BA2（用户实测 ✓，2026-10-09）：**被上层子页覆盖时，本层内容要"瞬间让位"** ✗→✓ ——
          // 用户对照截图指出：设置页原本的效果是"**旧内容瞬间消失 + 新内容横切进来**"✓，
          // 而右栏这一层**仍在绘制** ✗ → 又因四个外观子页在"有背景"时**本身是透明的** ✓，
          // 旧内容便从新页透明区**透出来、与新页重叠** ✗（用户原话："新切入的动画会被原本页面的内容
          // 侵入、重叠在一起，不好看"✓）。
          // 修法 ✓：用本条路由的 **`secondaryAnimation`**（= 被上层覆盖的进度 ✓）让本层
          // **在前 12% 内快速淡出** ✓ → 等价于"旧内容瞬间消失" ✓；返回时它反向恢复 ✓。
          // ⚠️ 本层**自己**的进出仍由 `animation` 驱动 ✗ —— 这里**不改** `animation` ✓，
          // 所以"设置项之间的切换"依旧零时长、行为不变 ✓。
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
                  CurvedAnimation(
                    parent: secondaryAnimation,
                    curve: const Interval(0.0, 0.12, curve: Curves.easeOut),
                  ),
                ),
                child: child,
              ),
        );
      },
    );
  }

  Widget _buildSettingsContent(int pageIndex) {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const NetworkSettings(),
      6 => const AboutSettings(),
      7 => const DebugPage(),
      _ => throw UnimplementedError(),
    };
  }
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：本控件的外观由设置算出 → 设置变化时由框架精准重建
    // （见 doc-private/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    return Material(color: customBackgroundAware(null), child: _buildPage());
  }

  Widget _buildPage() {
    return switch (pageIndex) {
      0 => const ExploreSettings(),
      1 => const ReaderSettings(),
      2 => const AppearanceSettings(),
      3 => const LocalFavoritesSettings(),
      4 => const AppSettings(),
      5 => const NetworkSettings(),
      6 => const AboutSettings(),
      7 => const DebugPage(),
      _ => throw UnimplementedError(),
    };
  }
}
