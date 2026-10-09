import 'dart:convert';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/consts.dart';
import 'package:venera_nas/foundation/favorites.dart';
import 'package:venera_nas/foundation/history.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/foundation/res.dart';
import 'package:venera_nas/network/download.dart';
import 'package:venera_nas/network/cache.dart';
import 'package:venera_nas/pages/comic_details_page/comic_page.dart';
import 'package:venera_nas/pages/reader/reader.dart';
import 'package:venera_nas/pages/settings/settings_page.dart';
import 'package:venera_nas/utils/ext.dart';
import 'package:venera_nas/utils/io.dart';
import 'package:venera_nas/utils/opencc.dart';
import 'package:venera_nas/utils/tags_translation.dart';
import 'package:venera_nas/utils/translations.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

part 'favorite_actions.dart';
part 'side_bar.dart';
part 'local_favorites_page.dart';
part 'network_favorites_page.dart';

const _kLeftBarWidth = 256.0;

const _kTwoPanelChangeWidth = 720.0;

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String? folder;

  bool isNetwork = false;

  FolderList? folderList;

  void setFolder(bool isNetwork, String? folder) {
    setState(() {
      this.isNetwork = isNetwork;
      this.folder = folder;
    });
    folderList?.update();
    appdata.implicitData['favoriteFolder'] = {
      'name': folder,
      'isNetwork': isNetwork,
    };
    appdata.writeImplicitData();
  }

  @override
  void initState() {
    var data = appdata.implicitData['favoriteFolder'];
    if (data != null) {
      folder = data['name'];
      isNetwork = data['isNetwork'] ?? false;
    }
    if (folder != null &&
        !isNetwork &&
        folder != _localAllFolderLabel &&
        !LocalFavoritesManager().existsFolder(folder!)) {
      folder = null;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：本控件的外观由设置算出 → 设置变化时由框架精准重建
    // （见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md）
    AppSettingsScope.of(context);
    return IconTheme(
      // A8：收藏页侧栏等图标的颜色走统一入口 ✓（全局「图标颜色」优先 ✓，
      // 未设置回退 `secondary` ✓；原先写死 secondary ✗ → 不跟随设置 ✓）
      data: IconThemeData(
        color: appIconColor(context, Theme.of(context).colorScheme.secondary),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            left: context.width <= _kTwoPanelChangeWidth ? -_kLeftBarWidth : 0,
            top: 0,
            bottom: 0,
            duration: AppMotion.short,
            child: (const _LeftBar()).fixWidth(_kLeftBarWidth),
          ),
          Positioned(
            top: 0,
            left: context.width <= _kTwoPanelChangeWidth ? 0 : _kLeftBarWidth,
            right: 0,
            bottom: 0,
            child: buildBody(),
          ),
        ],
      ),
    );
  }

  void showFolderSelector() {
    Navigator.of(App.rootContext).push(
      PageRouteBuilder(
        barrierDismissible: true,
        fullscreenDialog: true,
        opaque: false,
        barrierColor: appdata.settings.customBackgroundActive
            ? Colors.transparent
            : Colors.black.toOpacity(0.36),
        pageBuilder: (context, animation, secondary) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Material(
              // 修复（2026-10-09，用户实测）：窄屏时本侧栏是**浮层**（push 在正文页之上的路由）✓，
              // 而 `customBackgroundAware(null)` 在开启背景体系时返回 Colors.transparent ✗
              // ⇒ 下方正文（漫画列表）整片透出 ✗ = 用户报告的「侧边栏与主页重叠」✓。
              // 浮层必须给**不透明**表面色 ✓：用主题表面色（与项目其它弹层回退一致 ✓）；
              // 侧栏条目仍各自叠 `windowOverlayColor()` ✓，观感层次不变 ✓。
              // 宽屏双栏模式**不走这条路由** ✗ ⇒ 双栏外观零变化 ✓。
              color: context.colorScheme.surface,
              child: SizedBox(
                width: min(300, context.width - 16),
                child: _LeftBar(
                  withAppbar: true,
                  favPage: this,
                  onSelected: () {
                    context.pop();
                  },
                ),
              ),
            ),
          );
        },
        transitionsBuilder: (context, animation, secondary, child) {
          var offset = Tween<Offset>(
            begin: const Offset(-1, 0),
            end: const Offset(0, 0),
          );
          return SlideTransition(
            position: offset.animate(
              CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget buildBody() {
    if (folder == null) {
      return CustomScrollView(
        slivers: [
          SliverAppbar(
            leading: Tooltip(
              message: "Folders".tl,
              child: context.width <= _kTwoPanelChangeWidth
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      color: appIconColor(context, context.colorScheme.primary),
                      onPressed: showFolderSelector,
                    )
                  : null,
            ),
            title: GestureDetector(
              onTap: context.width < _kTwoPanelChangeWidth
                  ? showFolderSelector
                  : null,
              child: Text("Unselected".tl),
            ),
          ),
        ],
      );
    }
    if (!isNetwork) {
      return _LocalFavoritesPage(
        folder: folder!,
        key: PageStorageKey("local_$folder"),
      );
    } else {
      var favoriteData = getFavoriteDataOrNull(folder!);
      if (favoriteData == null) {
        folder = null;
        return buildBody();
      } else {
        return NetworkFavoritePage(
          favoriteData,
          key: PageStorageKey("network_$folder"),
        );
      }
    }
  }
}

abstract interface class FolderList {
  void update();

  void updateFolders();
}
