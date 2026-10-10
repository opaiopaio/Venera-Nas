part of 'favorites_page.dart';

class _LeftBar extends StatefulWidget {
  const _LeftBar({this.favPage, this.onSelected, this.withAppbar = false});

  final _FavoritesPageState? favPage;

  final VoidCallback? onSelected;

  final bool withAppbar;

  @override
  State<_LeftBar> createState() => _LeftBarState();
}

class _LeftBarState extends State<_LeftBar> implements FolderList {
  late _FavoritesPageState favPage;

  var folders = <String>[];

  var networkFolders = <String>[];

  void findNetworkFolders() {
    networkFolders.clear();
    var all = ComicSource.all()
        .where((e) => e.favoriteData != null)
        .map((e) => e.favoriteData!.key)
        .toList();
    var settings = appdata.settings['favorites'] as List;
    for (var p in settings) {
      if (all.contains(p) && !networkFolders.contains(p)) {
        networkFolders.add(p);
      }
    }
  }

  @override
  void initState() {
    favPage =
        widget.favPage ??
        context.findAncestorStateOfType<_FavoritesPageState>()!;
    favPage.folderList = this;
    folders = LocalFavoritesManager().folderNames;
    findNetworkFolders();
    appdata.settings.addListener(updateFolders);
    LocalFavoritesManager().addListener(updateFolders);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    appdata.settings.removeListener(updateFolders);
    LocalFavoritesManager().removeListener(updateFolders);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Column(
        children: [
          if (widget.withAppbar)
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const CloseButton(),
                  const SizedBox(width: 8),
                  Text("Folders".tl, style: ts.s18),
                ],
              ),
            ).paddingTop(context.padding.top),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.builder(
                padding: widget.withAppbar
                    ? EdgeInsets.zero
                    : EdgeInsets.only(top: context.padding.top),
                itemCount: folders.length + networkFolders.length + 3,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return buildLocalTitle();
                  }
                  index--;
                  if (index == 0) {
                    return buildLocalFolder(_localAllFolderLabel);
                  }
                  index--;
                  if (index < folders.length) {
                    return buildLocalFolder(folders[index]);
                  }
                  index -= folders.length;
                  if (index == 0) {
                    return buildNetworkTitle();
                  }
                  index--;
                  return buildNetworkFolder(networkFolders[index]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLocalTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          // C1：侧栏图标走统一取色 ✓（全局「图标颜色」优先，未设置回退 secondary ✓；
          // 原先写死 secondary ✗ → 用户实测"不跟随图标颜色" ✗）
          Icon(
            Icons.local_activity,
            color: appIconColor(context, context.colorScheme.secondary),
          ),
          const SizedBox(width: 12),
          Text("Local".tl),
          const Spacer(),
          MenuButton(
            entries: [
              MenuEntry(
                icon: Icons.add,
                text: 'Create Folder'.tl,
                onClick: () {
                  newFolder().then((value) {
                    setState(() {
                      folders = LocalFavoritesManager().folderNames;
                    });
                  });
                },
              ),
              MenuEntry(
                icon: Icons.reorder,
                text: 'Sort'.tl,
                onClick: () {
                  sortFolders().then((value) {
                    setState(() {
                      folders = LocalFavoritesManager().folderNames;
                    });
                  });
                },
              ),
            ],
          ),
        ],
      ).paddingHorizontal(16),
    );
  }

  Widget buildNetworkTitle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      margin: const EdgeInsets.only(top: AppSpace.sm),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Row(
        children: [
          // C1：同上 —— 侧栏「网络」小云图标 ✓（原先写死 secondary ✗）
          Icon(
            Icons.cloud,
            color: appIconColor(context, context.colorScheme.secondary),
          ),
          const SizedBox(width: 12),
          Text("Network".tl),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showPopUpWidget(App.rootContext, setFavoritesPagesWidget());
            },
          ),
        ],
      ).paddingHorizontal(16),
    );
  }

  /// 本地与网络文件夹行的**统一外壳** ✓ —— `buildLocalFolder` 与 `buildNetworkFolder`
  /// 原先逐字复制了同一套 `InkWell + Container` 外观 ✓；现收编为唯一实现 ✓。
  ///
  /// ⚠️ 逐项 1:1 复现（**外观零变化** ✓）：`height: 42` ✓、`alignment: centerLeft` ✓、
  /// `margin` 随 `customBackgroundActive` ✓、底色 `primaryContainer.toOpacity(0.36)` 或
  /// `windowOverlayColor()` ✓、圆角 `windowOverlayBorderRadius()` ✓、未启用自定义背景时的
  /// 左侧 2px `primary` 竖条 ✓、`padding: only(left: AppSpace.lg)` ✓。
  /// 两者唯一的行内容差异由调用方以 `child` 传入 ✓：本地行是名字加计数角标 ✓，网络行只有标题 ✓。
  Widget _buildFolderRow({
    required bool isSelected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.centerLeft,
        margin: appdata.settings.customBackgroundActive
            ? const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.xxs,
              )
            : null,
        decoration: BoxDecoration(
          color: isSelected
              ? context.colorScheme.primaryContainer.toOpacity(0.36)
              : windowOverlayColor(),
          // 跟随「圆角/直角」设置（未启用自定义背景时为 null，保持原样）。
          borderRadius: windowOverlayBorderRadius(),
          border: appdata.settings.customBackgroundActive
              ? null
              : Border(
                  left: BorderSide(
                    color: isSelected
                        ? context.colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
        ),
        padding: const EdgeInsets.only(left: AppSpace.lg),
        child: child,
      ),
    );
  }

  Widget buildLocalFolder(String name) {
    bool isSelected = name == favPage.folder && !favPage.isNetwork;
    int count = 0;
    if (name == _localAllFolderLabel) {
      count = LocalFavoritesManager().totalComics;
    } else {
      count = LocalFavoritesManager().folderComics(name);
    }
    var folderName = name == _localAllFolderLabel
        ? "All".tl
        : getFavoriteDataOrNull(name)?.title ?? name;
    return _buildFolderRow(
      isSelected: isSelected,
      onTap: () {
        if (isSelected) {
          return;
        }
        favPage.setFolder(false, name);
        widget.onSelected?.call();
      },
      child: Row(
        children: [
          Expanded(child: Text(folderName)),
          Container(
            margin: EdgeInsets.only(right: AppSpace.sm),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xxs,
            ),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(count.toString()),
          ),
        ],
      ),
    );
  }

  Widget buildNetworkFolder(String key) {
    var data = getFavoriteDataOrNull(key);
    if (data == null) {
      return const SizedBox();
    }
    bool isSelected = key == favPage.folder && favPage.isNetwork;
    return _buildFolderRow(
      isSelected: isSelected,
      onTap: () {
        if (isSelected) {
          return;
        }
        favPage.setFolder(true, key);
        widget.onSelected?.call();
      },
      child: Text(data.title),
    );
  }

  @override
  void update() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void updateFolders() {
    if (!mounted) return;
    setState(() {
      folders = LocalFavoritesManager().folderNames;
      findNetworkFolders();
    });
  }
}
