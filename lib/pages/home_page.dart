import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/consts.dart';
import 'package:venera_nas/foundation/favorites.dart';
import 'package:venera_nas/foundation/history.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/foundation/read_later.dart';
import 'package:venera_nas/pages/comic_details_page/comic_page.dart';
import 'package:venera_nas/pages/comic_archive_page.dart';
import 'package:venera_nas/pages/comic_source_page.dart';
import 'package:venera_nas/pages/downloading_page.dart';
import 'package:venera_nas/pages/follow_updates_page.dart';
import 'package:venera_nas/pages/history_page.dart';
import 'package:venera_nas/pages/image_favorites_page/image_favorites_page.dart';
import 'package:venera_nas/pages/search_page.dart';
import 'package:venera_nas/utils/data_sync.dart';
import 'package:venera_nas/utils/comic_backup.dart';
import 'package:venera_nas/utils/import_comic.dart';
import 'package:venera_nas/utils/io.dart';
import 'package:venera_nas/utils/tags_translation.dart';
import 'package:venera_nas/utils/translations.dart';

import 'local_comics_page.dart';
import 'local_comics/import_dialog.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var widget = SmoothCustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: context.padding.top)),
        const _SearchBar(),
        const _SyncDataWidget(),
        const _ReadLater(),
        const _History(),
        const _Local(),
        const FollowUpdatesWidget(),
        const _ComicSourceWidget(),
        const ImageFavorites(),
        const _ComicArchiveWidget(),
        SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
      ],
    );
    // 顶部边界由 WindowFrame 全局统一处理（内容整体已在标题栏之下），此处无需让位。
    return context.width > changePoint ? widget.paddingHorizontal(8) : widget;
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        // 自适应：最小高度 + 随文字撑开（默认字号外观不变）
        constraints: BoxConstraints(minHeight: App.isMobile ? 52 : 46),
        width: double.infinity,
        margin: EdgeInsets.only(
          left: AppSpace.sm,
          right: AppSpace.sm,
          bottom: AppSpace.sm,
        ),
        child: Material(
          color: appdata.settings.customBackgroundActive
              ? windowOverlayColor()
              : context.colorScheme.surfaceContainerHigh,
          // 自定义背景时给搜索框加一道浅色描边，与下面「历史/本地」等分区卡片一致，
          // 避免变成完全透明看不出边界。
          shape: appdata.settings.customBackgroundActive
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                  side: BorderSide(color: context.colorScheme.outlineVariant),
                )
              : null,
          borderRadius: appdata.settings.customBackgroundActive
              ? null
              : BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () {
              context.to(() => const SearchPage());
            },
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Text('Search'.tl, style: ts.s16),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncDataWidget extends StatefulWidget {
  const _SyncDataWidget();

  @override
  State<_SyncDataWidget> createState() => _SyncDataWidgetState();
}

class _SyncDataWidgetState extends State<_SyncDataWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    DataSync().addListener(update);
    WidgetsBinding.instance.addObserver(this);
    lastCheck = DateTime.now();
  }

  void update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    super.dispose();
    DataSync().removeListener(update);
    WidgetsBinding.instance.removeObserver(this);
  }

  late DateTime lastCheck;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (DateTime.now().difference(lastCheck) > const Duration(minutes: 10)) {
        lastCheck = DateTime.now();
        DataSync().downloadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = DataSync().statusSnapshot;
    Widget child;
    if (!syncStatus.shouldShow) {
      child = const SliverPadding(padding: EdgeInsets.zero);
    } else if (syncStatus.isSyncing) {
      child = SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: windowOverlayColor(),
            border: Border.all(color: Theme.of(context).colorScheme.primary),
            borderRadius:
                windowOverlayBorderRadius() ??
                BorderRadius.circular(AppRadius.md),
          ),
          child: ListTile(
            // C2：同步图标走统一取色 ✓（未设置时回退**主题强调色** ✓ ——
            // 与本页其它图标/箭头一致 ✓；之前无显式色 → 落到 `ListTileThemeData.iconColor`
            // 的兜底近黑色 ✗，观感"固定黑"、与整页不搭 ✗，用户实测反馈 ✓）
            leading: Icon(
              Icons.sync,
              color: appIconColor(context, context.colorScheme.primary),
            ),
            title: Text(syncStatus.title.tl),
            subtitle: buildSyncStatusSubtitle(syncStatus),
            trailing: const CircularProgressIndicator(
              strokeWidth: 2,
            ).fixWidth(18).fixHeight(18),
          ),
        ),
      );
    } else if (App.isMobile) {
      child = SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: windowOverlayColor(),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius:
                windowOverlayBorderRadius() ??
                BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                // C2：同上（移动端布局）✓
                Icon(
                  Icons.sync,
                  color: appIconColor(context, context.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(syncStatus.title.tl, style: ts.s16),
                      buildSyncStatusSubtitle(syncStatus),
                    ],
                  ),
                ),
                if (syncStatus.lastError != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    onTap: () {
                      showDialogMessage(
                        App.rootContext,
                        "Error".tl,
                        syncStatus.lastError!,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm,
                        vertical: AppSpace.xs,
                      ),
                      decoration: BoxDecoration(
                        color: context.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Icon(
                        Icons.error_outline,
                        // ⭐ 图标取色（2026-10-11）：先让「全局图标颜色」优先 ✓（未设时仍用错误色 ✓）。
                        color: appIconColor(context, context.colorScheme.error),
                        size: AppIconSize.sm,
                      ),
                    ),
                  ).paddingRight(4),
                IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  onPressed: () async {
                    DataSync().uploadDataManually();
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined),
                  onPressed: () async {
                    DataSync().downloadDataManually();
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );
    } else {
      child = SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: windowOverlayColor(),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius:
                windowOverlayBorderRadius() ??
                BorderRadius.circular(AppRadius.md),
          ),
          child: ListTile(
            // C2：同步图标走统一取色 ✓（未设置时回退**主题强调色** ✓ ——
            // 与本页其它图标/箭头一致 ✓；之前无显式色 → 落到 `ListTileThemeData.iconColor`
            // 的兜底近黑色 ✗，观感"固定黑"、与整页不搭 ✗，用户实测反馈 ✓）
            leading: Icon(
              Icons.sync,
              color: appIconColor(context, context.colorScheme.primary),
            ),
            title: Text(syncStatus.title.tl),
            subtitle: buildSyncStatusSubtitle(syncStatus),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (syncStatus.lastError != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    onTap: () {
                      showDialogMessage(
                        App.rootContext,
                        "Error".tl,
                        syncStatus.lastError!,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm,
                        vertical: AppSpace.xs,
                      ),
                      decoration: BoxDecoration(
                        color: context.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      // ⭐ 对比度（2026-10-11）：同步错误胶囊自绘底色 ⇒ 文字取与填充成对的前景色 ✓
                      //（原先无颜色 ⇒ 继承全局文字色 ✗ ⇒ 浅色胶囊底上"白字融底"看不见 ✗）
                      child: FilledForeground(
                        fill: context.colorScheme.errorContainer,
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              // ⭐ 图标取色（2026-10-11）：先让「全局图标颜色」优先 ✓。
                              color: appIconColor(
                                context,
                                context.colorScheme.error,
                              ),
                              size: AppIconSize.sm,
                            ),
                            const SizedBox(width: 4),
                            Text('Error'.tl, style: ts.s12),
                          ],
                        ),
                      ),
                    ),
                  ).paddingRight(4),
                IconButton(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  onPressed: () async {
                    DataSync().uploadDataManually();
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.cloud_download_outlined),
                  onPressed: () async {
                    DataSync().downloadDataManually();
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );
    }
    return SliverAnimatedPaintExtent(duration: AppMotion.short, child: child);
  }

  String buildSyncStatusDetail(DataSyncStatusSnapshot status) {
    if (status.isUploading) return 'Uploading data...'.tl;
    if (status.isDownloading) return 'Downloading data...'.tl;
    if (status.lastError != null) {
      return '${'Last sync failed'.tl}: ${status.lastError}';
    }
    if (status.lastSyncTime <= 0) return 'Not synced yet'.tl;
    return '${'Last synced'.tl}: ${status.formattedLastSyncTime}';
  }

  Widget buildSyncStatusSubtitle(DataSyncStatusSnapshot status) {
    return Text(
      buildSyncStatusDetail(status),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _History extends StatefulWidget {
  const _History();

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  late List<History> history;
  late int count;

  void onHistoryChange() {
    if (mounted) {
      setState(() {
        history = HistoryManager().getRecent();
        count = HistoryManager().count();
      });
    }
  }

  @override
  void initState() {
    history = HistoryManager().getRecent();
    count = HistoryManager().count();
    HistoryManager().addListener(onHistoryChange);
    super.initState();
  }

  @override
  void dispose() {
    HistoryManager().removeListener(onHistoryChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: HomeSectionCard(
        title: 'History'.tl,
        count: count,
        onTap: () {
          context.to(() => const HistoryPage());
        },
        content: history.isNotEmpty
            ? ComicHorizontalList(
                comics: history,
                heroTagPrefix: 'history_',
                onItemTap: (comic, heroID) {
                  context.to(
                    () => ComicPage(
                      id: comic.id,
                      sourceKey: comic.sourceKey,
                      cover: comic.cover,
                      title: comic.title,
                      heroID: heroID,
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }
}

class _Local extends StatefulWidget {
  const _Local();

  @override
  State<_Local> createState() => _LocalState();
}

class _LocalState extends State<_Local> {
  late List<LocalComic> local;
  late int count;

  void onLocalComicsChange() {
    setState(() {
      local = LocalManager().getRecent();
      count = LocalManager().count;
    });
  }

  @override
  void initState() {
    local = LocalManager().getRecent();
    count = LocalManager().count;
    LocalManager().addListener(onLocalComicsChange);
    super.initState();
  }

  @override
  void dispose() {
    LocalManager().removeListener(onLocalComicsChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: HomeSectionCard(
        title: 'Local'.tl,
        count: count,
        onTap: () {
          context.to(() => const LocalComicsPage());
        },
        content: local.isNotEmpty
            ? ComicHorizontalList(
                comics: local,
                heroTagPrefix: 'local_',
                onItemTap: (comic, heroID) {
                  if (comic is LocalComic) {
                    comic.read();
                  }
                },
              )
            : null,
        actions: Row(
          children: [
            if (LocalManager().downloadingTasks.isNotEmpty)
              Button.outlined(
                child: Row(
                  children: [
                    if (LocalManager().downloadingTasks.first.isPaused)
                      const Icon(
                        Icons.pause_circle_outline,
                        size: AppIconSize.sm,
                      )
                    else
                      const _AnimatedDownloadingIcon(),
                    const SizedBox(width: 8),
                    Text(
                      "@a Tasks".tlParams({
                        'a': LocalManager().downloadingTasks.length,
                      }),
                    ),
                  ],
                ),
                onPressed: () {
                  showPopUpWidget(context, const DownloadingPage());
                },
              ),
            const Spacer(),
            // P8：动作按钮统一用**应用自己的 `Button`**（唯一实现 ✓）——
            // 高度 40 / 遮罩底色 / 全局文字色 / 文字居中 / 胶囊 全部内置 ✓，
            // 与设置页等处**完全同款**（此前用 `FilledButton.tonal` 走 M3 默认，
            // 与主题注入存在差异 ✗ → 用户实测"主页 32、其余 40"不一致 ✗）。
            Button.normal(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const SmbImportDialog(),
                );
              },
              child: Text("扫描 NAS".tl),
            ),
            const SizedBox(width: AppSpace.sm),
            Button.normal(onPressed: import, child: Text("Import".tl)),
          ],
        ).paddingHorizontal(AppSpace.lg).paddingVertical(AppSpace.sm),
      ),
    );
  }

  void import() {
    showDialog(
      barrierDismissible: false,
      context: App.rootContext,
      builder: (context) {
        return const _ImportComicsWidget();
      },
    );
  }
}

class _ComicArchiveWidget extends StatefulWidget {
  const _ComicArchiveWidget();

  @override
  State<_ComicArchiveWidget> createState() => _ComicArchiveWidgetState();
}

class _ComicArchiveWidgetState extends State<_ComicArchiveWidget> {
  List<BackupFile>? files;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!BackupConfig.fromSettings().isValid) return;
    final result = await ComicBackupManager.listBackups();
    if (!mounted) return;
    setState(() {
      if (result.success) {
        files = result.data;
        error = null;
      } else {
        files = null;
        error = result.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!BackupConfig.fromSettings().isValid) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }
    final currentFiles = files ?? const <BackupFile>[];
    final totalSize = currentFiles.fold<int>(0, (sum, file) => sum + file.size);
    final newest = currentFiles.isEmpty ? null : currentFiles.first.modified;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text("Comic Archive".tl),
          subtitle: Text(
            error != null
                ? error!
                : currentFiles.isEmpty
                ? "No archive files".tl
                : "@a archives · @b".tlParams({
                        'a': currentFiles.length,
                        'b': bytesToReadableString(totalSize),
                      }) +
                      (newest == null
                          ? ''
                          : '\n${"Latest".tl}: ${_formatTime(newest)}'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            context.to(() => const ComicArchivePage()).then((_) => load());
          },
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)}';
  }
}

class _ImportComicsWidget extends StatefulWidget {
  const _ImportComicsWidget();

  @override
  State<_ImportComicsWidget> createState() => _ImportComicsWidgetState();
}

class _ImportComicsWidgetState extends State<_ImportComicsWidget> {
  int type = 0;

  bool loading = false;

  var key = GlobalKey();

  var height = 200.0;

  var folders = LocalFavoritesManager().folderNames;

  String? selectedFolder;

  bool copyToLocalFolder = true;

  bool cancelled = false;

  @override
  void dispose() {
    loading = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String info = [
      "Select a directory which contains the comic files.".tl,
      "Select a directory which contains the comic directories.".tl,
      "Select an archive file (cbz, zip, 7z, cb7)".tl,
      "Select a directory which contains multiple archive files.".tl,
      "Select an EhViewer database and a download folder.".tl,
      "Scan the current local path and restore the local database.".tl,
    ][type];
    List<String> importMethods = [
      "Single Comic".tl,
      "Multiple Comics".tl,
      "An archive file".tl,
      "Multiple archive files".tl,
      "EhViewer downloads".tl,
      "Restore local downloads".tl,
    ];

    return ContentDialog(
      dismissible: !loading,
      title: "Import Comics".tl,
      content: loading
          ? SizedBox(
              width: 600,
              height: height,
              child: const Center(child: CircularProgressIndicator()),
            )
          : RadioGroup<int>(
              groupValue: type,
              onChanged: (value) {
                setState(() {
                  type = value ?? type;
                  if (type == 5) {
                    selectedFolder = null;
                  }
                });
              },
              child: Column(
                key: key,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 600),
                  ...List.generate(importMethods.length, (index) {
                    return RadioListTile<int>(
                      title: Text(importMethods[index]),
                      value: index,
                    );
                  }),
                  if (type != 4 && type != 5)
                    ListTile(
                      title: Text("Add to favorites".tl),
                      trailing: Select(
                        current: selectedFolder,
                        values: folders,
                        minWidth: 112,
                        onTap: (v) {
                          setState(() {
                            selectedFolder = folders[v];
                          });
                        },
                      ),
                    ).paddingHorizontal(8),
                  if (!App.isIOS &&
                      !App.isMacOS &&
                      type != 2 &&
                      type != 3 &&
                      type != 5)
                    CheckboxListTile(
                      enabled: true,
                      title: Text("Copy to app local path".tl),
                      value: copyToLocalFolder,
                      onChanged: (v) {
                        setState(() {
                          copyToLocalFolder = !copyToLocalFolder;
                        });
                      },
                    ).paddingHorizontal(8),
                  const SizedBox(height: 8),
                  Text(info).paddingHorizontal(24),
                ],
              ),
            ),
      actions: [
        Button.text(
          child: Row(
            children: [
              Icon(
                Icons.help_outline,
                size: AppIconSize.sm,
                color: appIconColor(context, context.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Text("help".tl),
            ],
          ),
          onPressed: () {
            launchUrlString(
              "https://github.com/haukuen/venera/blob/main/doc/import_comic.md",
            );
          },
        ).fixWidth(90).paddingRight(8),
        Button.filled(
          isLoading: loading,
          onPressed: selectAndImport,
          child: Text("Select".tl),
        ),
      ],
    );
  }

  void selectAndImport() async {
    // ⭐ 修复（2026-10-10 全量代码审查 ✓）：**去掉双重空断言** ✗→✓ ——
    // `key.currentContext!.size!` 在浮层尚未首帧构建时会直接抛 null check ✗；改为可选链并保留原值 ✓。
    height = key.currentContext?.size?.height ?? height;

    setState(() {
      loading = true;
    });
    var importer = ImportComic(
      selectedFolder: selectedFolder,
      copyToLocal: copyToLocalFolder,
    );
    var result = switch (type) {
      0 => await importer.directory(true),
      1 => await importer.directory(false),
      2 => await importer.cbz(),
      3 => await importer.multipleCbz(),
      4 => await importer.ehViewer(),
      5 => await importer.localDownloads(),
      int() => true,
    };
    if (result) {
      if (!mounted) return;
      context.pop();
    } else {
      // ⭐ 修复（2026-10-10 全量代码审查 ✓）：**失败分支也要查存活** ✗→✓ ——
      // 导入可能长达数分钟，且系统目录选择器会让本 State 失焦 ✓；用户取消/按 Esc/点遮罩都会卸载本 State ✗
      // ⇒ 原先此处无守卫的 `setState` 会崩 ✓（成功分支本就有守卫 ✓）。
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }
}

class _ComicSourceWidget extends StatefulWidget {
  const _ComicSourceWidget();

  @override
  State<_ComicSourceWidget> createState() => _ComicSourceWidgetState();
}

class _ComicSourceWidgetState extends State<_ComicSourceWidget> {
  late List<String> comicSources;

  void onComicSourceChange() {
    setState(() {
      comicSources = ComicSource.all().map((e) => e.name).toList();
    });
  }

  @override
  void initState() {
    comicSources = ComicSource.all().map((e) => e.name).toList();
    ComicSourceManager().addListener(onComicSourceChange);
    super.initState();
  }

  @override
  void dispose() {
    ComicSourceManager().removeListener(onComicSourceChange);
    super.dispose();
  }

  int get _availableUpdates {
    int c = 0;
    ComicSourceManager().availableUpdates.forEach((key, version) {
      var source = ComicSource.find(key);
      if (source != null) {
        if (compareSemVer(version, source.version)) {
          c++;
        }
      }
    });
    return c;
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: HomeSectionCard(
        title: 'Comic Source'.tl,
        count: comicSources.length,
        onTap: () {
          context.to(() => const ComicSourcePage());
        },
        content: comicSources.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      runSpacing: AppSpace.sm,
                      spacing: AppSpace.sm,
                      children: comicSources.map((e) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm,
                            vertical: AppSpace.xxs,
                          ),
                          decoration: BoxDecoration(
                            // D1：首页标签走统一入口 ✓（可切跟随遮罩/主题 ✓）
                            color: tagFillColor(context),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          // ⭐ 对比度（2026-10-11）：自绘填充 ⇒ 文字取与填充成对的前景色 ✓；
                          // ⚠️ 用户设了全局文字色 ⇒ 优先跟随 ✓；填充透明 ⇒ 回退"继承环境样式" ✓（原语义 ✓）。
                          child: Text(
                            e,
                            style: TextStyle(
                              color:
                                  globalTextColor() ??
                                  fillForeground(
                                    context,
                                    tagFillColor(context),
                                  ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ).paddingHorizontal(AppSpace.lg).paddingBottom(AppSpace.lg),
                  if (_availableUpdates > 0)
                    Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm,
                            vertical: AppSpace.xs,
                          ),
                          decoration: BoxDecoration(
                            // ⭐ F1-①：本胶囊底色走「标签颜色」统一入口 ✓
                            // （跟随遮罩 `windowOverlayColor()` / 跟随主题 `secondaryContainer` ✓），
                            // 原先**只有描边、没有填充** ✗ → 不受「标签颜色」设置控制 ✗（用户实测反馈 ✓）。
                            color: tagFillColor(context),
                            border: Border.all(
                              color: context.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.update,
                                // F1-①：图标不再写死主题色 ✗ —— 与 `MaskChip`（分类页 tag ✓）同一约定：
                                // **继承**周边前景色（全局文字色/图标色 ✓）→ 底色切换时才看得出整体变化 ✓
                                //（原先 icon/text 都是 `colorScheme.primary` ✗ → 改底色后仍"看着像主题色" ✗，
                                //  用户实测反馈"切换没反应、依旧跟随主题" ✓）。
                                // ⭐ 对比度（2026-10-11）：胶囊自绘填充 ⇒ 图标也取与填充成对的前景色 ✓
                                //（用户设了图标色 ⇒ `appIconColor` 优先跟随 ✓；填充透明 ⇒ 回退继承 ✓）。
                                color: appIconColor(
                                  context,
                                  fillForeground(
                                    context,
                                    tagFillColor(context),
                                  ),
                                ),
                                size: AppIconSize.md,
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Text(
                                "@c updates".tlParams({'c': _availableUpdates}),
                                // ⭐ 对比度（2026-10-11）：自绘填充 ⇒ 文字取与填充成对的前景色 ✓；
                                // ⚠️ 用户设了全局文字色 ⇒ 优先跟随 ✓；填充透明 ⇒ 回退继承 ✓（原语义 ✓）。
                                style: TextStyle(
                                  color:
                                      globalTextColor() ??
                                      fillForeground(
                                        context,
                                        tagFillColor(context),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toAlign(Alignment.centerLeft)
                        .paddingHorizontal(AppSpace.lg)
                        .paddingBottom(AppSpace.sm),
                ],
              )
            : null,
      ),
    );
  }
}

class _AnimatedDownloadingIcon extends StatefulWidget {
  const _AnimatedDownloadingIcon();

  @override
  State<_AnimatedDownloadingIcon> createState() =>
      __AnimatedDownloadingIconState();
}

class __AnimatedDownloadingIconState extends State<_AnimatedDownloadingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      lowerBound: -1,
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Transform.translate(
            offset: Offset(0, 18 * _controller.value),
            child: Icon(
              Icons.arrow_downward,
              size: AppIconSize.xs,
              color: appIconColor(
                context,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class ImageFavorites extends StatefulWidget {
  const ImageFavorites({super.key});

  @override
  State<ImageFavorites> createState() => _ImageFavoritesState();
}

class _ImageFavoritesState extends State<ImageFavorites> {
  ImageFavoritesComputed? imageFavoritesCompute;

  int displayType = appdata.settings['imageFavoritesDisplayType'] as int;

  bool get _showChart =>
      appdata.settings['showImageFavoritesChart'] as bool? ?? true;

  void refreshImageFavorites() async {
    try {
      imageFavoritesCompute =
          await ImageFavoriteManager.computeImageFavorites();
      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      Log.error("Unhandled Exception", e.toString(), stackTrace);
    }
  }

  @override
  void initState() {
    refreshImageFavorites();
    ImageFavoriteManager().addListener(refreshImageFavorites);
    appdata.settings.addListener(_onSettingsChanged);
    super.initState();
  }

  @override
  void dispose() {
    ImageFavoriteManager().removeListener(refreshImageFavorites);
    appdata.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasData =
        imageFavoritesCompute != null && !imageFavoritesCompute!.isEmpty;
    return SliverToBoxAdapter(
      child: HomeSectionCard(
        title: 'Image Favorites'.tl,
        count: hasData ? imageFavoritesCompute!.count : null,
        onTap: () {
          context.to(() => const ImageFavoritesPage());
        },
        content: (hasData && _showChart)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      buildTypeButton(0, "Tags".tl),
                      const Spacer(),
                      buildTypeButton(1, "Authors".tl),
                      const Spacer(),
                      buildTypeButton(2, "Comics".tl),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  buildChart(switch (displayType) {
                    0 => imageFavoritesCompute!.tags,
                    1 => imageFavoritesCompute!.authors,
                    2 => imageFavoritesCompute!.comics,
                    _ => [],
                  }).paddingHorizontal(AppSpace.lg).paddingBottom(AppSpace.lg),
                ],
              )
            : null,
      ),
    );
  }

  Widget buildTypeButton(int type, String text) {
    const radius = 24.0;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: () async {
        setState(() {
          displayType = type;
        });
        appdata.settings['imageFavoritesDisplayType'] = type;
        appdata.saveData();
        await Future.delayed(const Duration(milliseconds: 20));
        if (!mounted) return;
        var scrollController = ScrollState.of(context).controller;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: AppMotion.short,
          curve: Curves.ease,
        );
      },
      child: AnimatedContainer(
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: displayType == type
              ? context.colorScheme.primaryContainer
              : null,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        duration: AppMotion.short,
        // ⭐ 对比度（2026-10-11）：选中态自绘 `primaryContainer` 底色 ⇒ 文字取与填充成对的前景色 ✓
        //（原先无颜色 ⇒ 继承全局文字色 ✗ ⇒ 浅色选中者底上"白字融底"看不见 ✗）；
        // ⭐ 这是**选中态标识**（选中一眼可辨靠的就是主题成对色 ✓）⇒ 「用户文字色」不得覆盖它 ✗；
        // 未选中（无填充 ✓）保持原语义 ✗ 不动。
        child: FilledForeground(
          fill: displayType == type
              ? context.colorScheme.primaryContainer
              : null,
          userColorWins: false,
          child: Center(child: Text(text, style: ts.s16)),
        ),
      ),
    );
  }

  Widget buildChart(List<TextWithCount> data) {
    if (data.isEmpty) {
      return const SizedBox();
    }
    var maxCount = data.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 164),
      child: SingleChildScrollView(
        child: Column(
          key: ValueKey(displayType),
          children: data.map((e) {
            return _ChartLine(
              text: e.text,
              count: e.count,
              maxCount: maxCount,
              enableTranslation: displayType != 2,
              onTap: (text) {
                context.to(() => ImageFavoritesPage(initialKeyword: text));
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ChartLine extends StatefulWidget {
  const _ChartLine({
    required this.text,
    required this.count,
    required this.maxCount,
    required this.enableTranslation,
    this.onTap,
  });

  final String text;

  final int count;

  final int maxCount;

  final bool enableTranslation;

  final void Function(String text)? onTap;

  @override
  State<_ChartLine> createState() => __ChartLineState();
}

class __ChartLineState extends State<_ChartLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.short,
      value: 0,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var text = widget.text;
    var enableTranslation =
        App.locale.countryCode == 'CN' && widget.enableTranslation;
    if (enableTranslation) {
      text = text.translateTagsToCN;
    }
    if (widget.enableTranslation && text.contains(':')) {
      text = text.split(':').last;
    }
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            widget.onTap?.call(widget.text);
          },
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)
              .paddingHorizontal(4)
              .toAlign(Alignment.centerLeft)
              .fixWidth(context.width > 600 ? 120 : 80)
              .fixHeight(double.infinity),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constrains) {
              var width = constrains.maxWidth * widget.count / widget.maxCount;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    width: width * _controller.value,
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: context.isDarkMode
                            ? [Colors.blue.shade800, Colors.blue.shade500]
                            : [Colors.blue.shade300, Colors.blue.shade600],
                      ),
                    ),
                  ).toAlign(Alignment.centerLeft);
                },
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          widget.count.toString(),
          style: ts.s12,
        ).fixWidth(context.width > 600 ? 60 : 30),
      ],
    ).fixHeight(28);
  }
}

class _ReadLater extends StatefulWidget {
  const _ReadLater();

  @override
  State<_ReadLater> createState() => _ReadLaterState();
}

class _ReadLaterState extends State<_ReadLater> {
  List<ReadLaterItem> items = [];
  int itemCount = 0;

  void _onDataChanged() {
    if (mounted) {
      setState(() {
        items = ReadLaterManager().getAll();
        itemCount = ReadLaterManager().count;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    items = ReadLaterManager().getAll();
    itemCount = ReadLaterManager().count;
    ReadLaterManager().addListener(_onDataChanged);
  }

  @override
  void dispose() {
    ReadLaterManager().removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverPadding(padding: EdgeInsets.zero);
    }

    return SliverToBoxAdapter(
      child: HomeSectionCard(
        title: 'Read Later'.tl,
        count: itemCount,
        onTap: () {
          context.to(() => const _ReadLaterPage());
        },
        content: ComicHorizontalList(
          comics: items,
          heroTagPrefix: 'readLater_',
          onItemTap: (comic, heroID) {
            context.to(
              () => ComicPage(
                id: comic.id,
                sourceKey: comic.sourceKey,
                cover: comic.cover,
                title: comic.title,
                heroID: heroID,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReadLaterPage extends StatefulWidget {
  const _ReadLaterPage();

  @override
  State<_ReadLaterPage> createState() => _ReadLaterPageState();
}

class _ReadLaterPageState extends State<_ReadLaterPage> {
  @override
  void initState() {
    ReadLaterManager().addListener(onUpdate);
    super.initState();
  }

  @override
  void dispose() {
    ReadLaterManager().removeListener(onUpdate);
    super.dispose();
  }

  var comics = ReadLaterManager().getAll();
  bool multiSelectMode = false;
  Map<ReadLaterItem, bool> selectedComics = {};

  void onUpdate() {
    if (mounted) {
      setState(() {
        comics = ReadLaterManager().getAll();
        selectedComics.removeWhere((comic, _) => !comics.contains(comic));
        if (selectedComics.isEmpty) {
          multiSelectMode = false;
        }
      });
    }
  }

  void selectAll() {
    setState(() {
      selectedComics = {for (var c in comics) c: true};
    });
  }

  void deSelect() {
    setState(() {
      selectedComics.clear();
    });
  }

  void invertSelection() {
    setState(() {
      for (var c in comics) {
        selectedComics[c] = !selectedComics.putIfAbsent(c, () => false);
      }
      selectedComics.removeWhere((k, v) => !v);
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> selectActions = [
      // ⭐ 外观构件统一 · 第二批（2026-10-10 ✓）：多选工具条改用**唯一实现** `SelectToolbar` ✓
      // —— 原本此处与其它 5 个页面逐行重复 ✓；按钮构造方式与原先**逐字一致** ⇒ 外观不变 ✓。
      SelectToolbar(
        onSelectAll: selectAll,
        onDeSelect: deSelect,
        onInvert: invertSelection,
        deleteEnabled: selectedComics.isNotEmpty,
        onDelete: () {
          final toDelete = List<ReadLaterItem>.from(selectedComics.keys);
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
          for (final comic in toDelete) {
            ReadLaterManager().remove(comic.id, comic.type);
          }
        },
      ),
    ];

    List<Widget> normalActions = [
      IconButton(
        icon: const Icon(Icons.checklist),
        tooltip: "Multi-Select".tl,
        onPressed: () {
          setState(() {
            multiSelectMode = !multiSelectMode;
          });
        },
      ),
      Tooltip(
        message: 'Clear'.tl,
        child: IconButton(
          icon: const Icon(Icons.clear_all),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) {
                return ContentDialog(
                  title: 'Clear'.tl,
                  content: Text(
                    'Are you sure you want to clear your read later list?'.tl,
                  ),
                  actions: [
                    Button.filled(
                      color: context.colorScheme.error,
                      onPressed: () {
                        ReadLaterManager().removeAll();
                        context.pop();
                      },
                      child: Text('Clear'.tl),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ];

    return PopScope(
      canPop: !multiSelectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (multiSelectMode) {
          setState(() {
            multiSelectMode = false;
            selectedComics.clear();
          });
        }
      },
      child: Scaffold(
        body: SmoothCustomScrollView(
          slivers: [
            SliverAppbar(
              leading: Tooltip(
                message: multiSelectMode ? "Cancel".tl : "Back".tl,
                child: IconButton(
                  onPressed: () {
                    if (multiSelectMode) {
                      setState(() {
                        multiSelectMode = false;
                        selectedComics.clear();
                      });
                    } else {
                      context.pop();
                    }
                  },
                  icon: multiSelectMode
                      ? const Icon(Icons.close)
                      : const Icon(Icons.arrow_back),
                ),
              ),
              title: multiSelectMode
                  ? Text(selectedComics.length.toString())
                  : Text('Read Later'.tl),
              actions: multiSelectMode ? selectActions : normalActions,
            ),
            if (comics.isEmpty)
              SliverToBoxAdapter(
                child: Center(child: Text('No items'.tl).paddingTop(200)),
              )
            else
              SliverGridComics(
                comics: comics,
                selections: selectedComics,
                onLongPressed: null,
                onTap: multiSelectMode
                    ? (c, heroID) {
                        setState(() {
                          if (selectedComics.containsKey(c as ReadLaterItem)) {
                            selectedComics.remove(c);
                          } else {
                            selectedComics[c] = true;
                          }
                          if (selectedComics.isEmpty) {
                            multiSelectMode = false;
                          }
                        });
                      }
                    : null,
                badgeBuilder: (c) {
                  return ComicSource.find(c.sourceKey)?.name;
                },
                menuBuilder: (c) {
                  return [
                    MenuEntry(
                      icon: Icons.remove,
                      text: 'Remove'.tl,
                      color: context.colorScheme.error,
                      onClick: () {
                        ReadLaterManager().remove(
                          c.id,
                          ComicType.fromKey(c.sourceKey),
                        );
                      },
                    ),
                  ];
                },
              ),
          ],
        ),
      ),
    );
  }
}
