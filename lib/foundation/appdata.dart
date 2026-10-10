import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:venera_nas/foundation/app.dart';
// ⭐ AR1（2026-10-09）：需要 `AppOpacity.tintStrengthDefault` 作为菜单色调强度的默认值 ✓
//（与二级页面同默认 ✓，避免写字面量 ✗ —— 外观铁律要求常量走 design_tokens ✓）。
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/utils/data_sync.dart';
import 'package:venera_nas/utils/init.dart';
import 'package:venera_nas/utils/io.dart';

class Appdata with Init {
  Appdata._create();

  final Settings settings = Settings._create();

  var searchHistory = <String>[];

  bool _isSavingData = false;

  Future<void> saveData([bool sync = true]) async {
    while (_isSavingData) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _isSavingData = true;
    try {
      var futures = <Future>[];
      var json = toJson();
      var data = jsonEncode(json);
      var file = File(FilePath.join(App.dataPath, 'appdata.json'));
      futures.add(file.writeAsString(data));

      // ⭐ 2026-10-10（回归审查 P0-1 ✓）：同步快照**无论如何都要生成** ✗→✓ ——
      // 原先只在用户自定义过 `disableSyncFields` 时才写 `syncdata.json` ✗，而该字段**默认是空串** ✓
      // ⇒ 上行退回**原始 `appdata.json`** ✗ ⇒ `deviceId` / 旧 `deviceSpecificSettings` 容器 /
      // 两个开关标志**全部进云端** ✓（= 用户报的"开关被同步过去" ✓）。
      // 现在 ✓：**始终**产出过滤后的 `syncdata.json`，且**只**剔除这几类 ✗ ——
      // 其余设置值（含 `backgroundImage` / `backgroundColor` ✓、webdav 等 ✓）**一律保留** ✓
      //（用户要求"同步文件都要包含所有页面的设置信息（值）" ✓ = 永远完整快照 ✓）。
      var json4sync = jsonDecode(data);
      var syncSettings = json4sync["settings"];
      if (syncSettings is Map) {
        final customDisableSync = splitField(
          syncSettings["disableSyncFields"] as String? ?? '',
        );
        for (var field in customDisableSync) {
          syncSettings.remove(field);
        }
        syncSettings.remove("deviceId");
        syncSettings.remove("deviceSpecificSettings");
        for (final field in _deviceSwitchFlagKeys) {
          syncSettings.remove(field);
        }
      }
      json4sync.remove("deviceSpecificSettings");
      json4sync.remove("deviceId");
      var data4sync = jsonEncode(json4sync);
      var file4sync = File(FilePath.join(App.dataPath, 'syncdata.json'));
      futures.add(file4sync.writeAsString(data4sync));

      await Future.wait(futures);
    } finally {
      _isSavingData = false;
    }
    if (sync) {
      DataSync().uploadData();
    }
  }

  void addSearchHistory(String keyword) {
    if (searchHistory.contains(keyword)) {
      searchHistory.remove(keyword);
    }
    searchHistory.insert(0, keyword);
    if (searchHistory.length > 50) {
      searchHistory.removeLast();
    }
    saveData();
  }

  void removeSearchHistory(String keyword) {
    searchHistory.remove(keyword);
    saveData();
  }

  void clearSearchHistory() {
    searchHistory.clear();
    saveData();
  }

  Map<String, dynamic> toJson() {
    return {'settings': settings._data, 'searchHistory': searchHistory};
  }

  List<String> splitField(String merged) {
    return merged
        .split(',')
        .map((field) => field.trim())
        .where((field) => field.isNotEmpty)
        .toList();
  }

  /// Fields that should not be restored from a local backup.
  static const _disableRestore = [
    "deviceId",
    "lastSyncTime",
    "disableSyncFields",
    "authorizationRequired",
    "smbDownloadPath",
    // ⭐ 2026-10-10（用户要求 + 回归审查 P1-6 ✓）：**背景图片相关**（文件名 + 本机选取路径）任何情况下都不应用 ✗ ——
    // 图**文件**不随同步/备份传输 ✓（只传文件名/路径 ✓）⇒ 应用了也只会指向本机不存在的图 ✗、
    // 设置页还会显示对端的选取路径 ✗ ⇒ 两者一起排除 ✓（`backgroundImage` 与 `backgroundImageSource` 必须同时 ✗）。
    // 注意：**背景色 `backgroundColor` 不在此列** ✓（用户特意强调"除了背景，但是不包括背景色，只有背景图片" ✓）。
    "backgroundImage",
    "backgroundImageSource",
    ..._deviceSwitchFlagKeys,
    // ⭐ 迁移用：旧版第二层容器（值已搬进主表 ✓，容器不再被读取 ✓）也一并排除 ✓。
    "deviceSpecificSettings",
  ];

  /// Restore data from a local backup file.
  /// Unlike [syncData], this restores most settings including webdav config.
  void restoreFromBackup(Map<String, dynamic> data) {
    if (data['settings'] is Map) {
      var settings = data['settings'] as Map<String, dynamic>;
      for (var key in settings.keys) {
        // ⭐ 重构（2026-10-10 用户方案 ✓）：**开关 ON 的受保护键不参与本地备份恢复** ✓ ——
        // 否则恢复一份备份会把本设备"特意留在本地"的外观/阅读值覆盖掉 ✗（= 开关形同虚设 ✗）。
        if (_disableRestore.contains(key) ||
            this.settings.isDeviceProtected(key)) {
          continue;
        }
        if (settings[key] != null) {
          this.settings._data[key] = settings[key];
        }
      }
    }
    searchHistory = List.from(data['searchHistory'] ?? []);
    saveData();
  }

  /// ⭐ 2026-10-10（用户要求 ✓）：**两个「启用设备特定设置」开关标志** ——
  /// 它们**永远只属于本机** ✗：既**不上传**（同步/备份快照里不含 ✓）、
  /// 也**不在入方向被应用** ✓（对端值落在本机时会被丢弃 ✓）。
  /// 用户原话 ✓："如果我设备 1 的该设置启动，那设备 2 通过云同步也就把他的设置自动打开了" ✗ —— 这就是要堵的洞 ✓。
  static const _deviceSwitchFlagKeys = <String>[
    "deviceSpecificAppearanceEnabled",
    "deviceSpecificReaderEnabled",
  ];

  /// ⭐ 2026-10-10（用户要求 ✓）：**入方向（同步进来 / 备份恢复）永不应用** 的键 ✓。
  ///
  /// 规则 ✓：出方向**永远生成完整快照**（所有页面的设置值都包含 ✓，见 `saveData` 与
  /// `utils/data_sync.dart` 的 `_backupLocalData` ✓）；**是否应用**则按**本机**开关决定 ✓
  ///（`syncData` / `restoreFromBackup` 里的 `isDeviceProtected` ✓：本机开关 ON ⇒ 跳过 ✓、OFF ⇒ 应用 ✓）。
  /// 本清单里的键则是**无论开关如何都不应用** ✓：
  /// - 代理 / WebDAV / 设备 id / 收藏显示等本机或凭据相关项 ✓；
  /// - **`backgroundImage`** ✗ —— 背景**图片**文件不随同步/备份传输 ✓（只传文件名 ✓），
  ///   应用了只会指向本机不存在的图 ✓；⚠️ **但 `backgroundColor`（背景色）与
  ///   `backgroundImageOpacity` / `backgroundImageFit` 不在此列** ✓ —— 用户明确要求
  ///   "除了背景（图片），不包括背景色" ✓ ⇒ 它们**要能**在本机开关关时被恢复 ✓（原先被误列在此 ✗ 已移除 ✓）。
  static const _disableSync = [
    "backgroundImage",
    "backgroundImageSource",
    "proxy",
    "authorizationRequired",
    "customImageProcessing",
    "webdav",
    "webdavProxyEnabled",
    "backupWebdav",
    "backupWebdavPath",
    "disableSyncFields",
    "deviceId",
    "lastSyncTime",
    "imageFavoritesDisplayType",
    "commentFontSize",
    "smbDownloadPath",
    ..._deviceSwitchFlagKeys,
    "deviceSpecificSettings",
  ];

  static const _archiveSyncFields = ["backupWebdav", "backupWebdavPath"];

  /// Sync data from another device
  void syncData(Map<String, dynamic> data) {
    if (data['settings'] is Map) {
      var settings = data['settings'] as Map<String, dynamic>;

      List<String> customDisableSync = splitField(
        this.settings["disableSyncFields"] as String,
      );

      // Read the local toggle BEFORE the loop so sync decisions are
      // based on the pre-sync local state.
      final archiveSyncEnabled =
          this.settings["backupWebdavSyncEnabled"] == true;

      for (var key in settings.keys) {
        if (_archiveSyncFields.contains(key)) {
          if (archiveSyncEnabled) {
            // ⭐ 同步/恢复写入**全局**（绕过设备分流 ✓），否则会把对端值写进本机设备表 ✓。
            this.settings._data[key] = settings[key];
          }
          continue;
        }
        // ⭐ 修复（2026-10-10 用户要求 ✓）：**双向阻隔 · 下行** ✗→✓ —— 本设备已启用该键所属的
        // 「设备特定设置」开关 ⇒ **云端的值不再覆盖本地** ✓（用户："云端有该设置的选项也不会覆盖本地这部分设置" ✓）。
        // 原先只做了"写入哪张表" ✓，同步合并时仍无条件写全局 ✗ ⇒ 启用前改过的项会被云端盖掉 ✓，观感即"依旧被覆盖" ✓。
        if (_disableSync.contains(key) || customDisableSync.contains(key)) {
          continue;
        }
        final deviceProtected = this.settings.isDeviceProtected(key);
        if (deviceProtected) continue;
        // ⭐ 同步/恢复写入**全局**（绕过设备分流 ✓），否则会把对端值写进本机设备表 ✓。
        this.settings._data[key] = settings[key];
      }
    }
    searchHistory = List.from(data['searchHistory'] ?? []);
    saveData();
  }

  var implicitData = <String, dynamic>{};

  Future<void> writeImplicitData() async {
    while (_isSavingData) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    _isSavingData = true;
    try {
      var file = File(FilePath.join(App.dataPath, 'implicitData.json'));
      await file.writeAsString(jsonEncode(implicitData));
    } finally {
      _isSavingData = false;
    }
  }

  @override
  Future<void> doInit() async {
    var dataPath = (await getApplicationSupportDirectory()).path;
    var file = File(FilePath.join(dataPath, 'appdata.json'));
    if (!await file.exists()) {
      return;
    }
    try {
      var json = jsonDecode(await file.readAsString());
      for (var key in (json['settings'] as Map<String, dynamic>).keys) {
        if (json['settings'][key] != null) {
          settings[key] = json['settings'][key];
        }
      }
      searchHistory = List.from(json['searchHistory']);
    } catch (e) {
      Log.error("Appdata", "Failed to load appdata", e);
      Log.info("Appdata", "Resetting appdata");
      file.deleteIgnoreError();
    }
    if ((settings["deviceId"] as String).isEmpty) {
      settings._data["deviceId"] = const Uuid().v4();
      await saveData(false);
    }
    // ⭐ 迁移（2026-10-10 用户方案 ✓）：把旧版**第二层**的值搬进主表并清空 ✓（幂等 ✓）——
    // 不搬的话老用户此前"只在设备层"的值（如背景 ✓）会在升级后消失 ✗。见 `_migrateDeviceSpecificSettings` ✓。
    if (settings._migrateDeviceSpecificSettings()) {
      await saveData(false);
    }
    try {
      var implicitDataFile = File(FilePath.join(dataPath, 'implicitData.json'));
      if (await implicitDataFile.exists()) {
        implicitData = jsonDecode(await implicitDataFile.readAsString());
      }
    } catch (e) {
      Log.error("Appdata", "Failed to load implicit data", e);
      Log.info("Appdata", "Resetting implicit data");
      var implicitDataFile = File(FilePath.join(dataPath, 'implicitData.json'));
      implicitDataFile.deleteIgnoreError();
    }
  }
}

final appdata = Appdata._create();

class Settings with ChangeNotifier {
  Settings._create();

  final _data = <String, dynamic>{
    'comicDisplayMode': 'detailed', // detailed, brief
    // 分章节导出的章节段命名格式，见 ChapterExportNamingFormat
    'chapterExportNamingFormat': 'ep', // ep, chinese, volume, number
    'comicTileScale': 1.00, // 0.75-1.25
    'color': 'system', // red, pink, purple, green, orange, blue
    'theme_mode': 'system', // light, dark, system
    'newFavoriteAddTo': 'end', // start, end
    'moveFavoriteAfterRead': 'none', // none, end, start
    'proxy': 'system', // direct, system, proxy string
    'explore_pages': [],
    'categories': [],
    'favorites': [],
    'searchSources': null,
    'showFavoriteStatusOnTile': true,
    'showHistoryStatusOnTile': false,
    'historyRetentionDays': 0, // 0 means disabled; 7-182 days
    'blockedWords': [],
    'blockedCommentWords': [],
    'defaultSearchTarget': null,
    'autoPageTurningInterval': 5, // in seconds
    'readerMode': 'galleryLeftToRight', // values of [ReaderMode]
    'readerScreenPicNumberForLandscape': 1, // 1 - 5
    'readerScreenPicNumberForPortrait': 1, // 1 - 5
    'enableTapToTurnPages': true,
    'reverseTapToTurnPages': false,
    'enablePageAnimation': true,
    'pageUpAndDownAction': 'chapter', // chapter, page, disabled
    'language': 'system', // system, zh-CN, zh-TW, en-US
    'cacheSize': 2048, // in MB
    'downloadThreads': 5,
    'enableLongPressToZoom': true,
    'longPressZoomPosition': "press", // press, center
    'checkUpdateOnStart': false,
    'limitImageWidth': true,
    'webdav': [], // empty means not configured
    'webdavProxyEnabled': true,
    'backupWebdav': [], // empty means not configured
    'backupWebdavPath': '/venera_backup/',
    'backupWebdavSyncEnabled': false,
    "disableSyncFields": "", // TODO: remove, UI entry has been deleted
    'dataVersion': 0,
    'lastSyncTime': 0,
    'quickFavorite': null,
    'enableTurnPageByVolumeKey': true,
    'enableClockAndBatteryInfoInReader': true,
    'quickCollectImage': 'No', // No, DoubleTap, Swipe
    'authorizationRequired': false,
    'onClickFavorite': 'viewDetail', // viewDetail, read
    'enableDnsOverrides': false,
    'dnsOverrides': {},
    'enableCustomImageProcessing': false,
    'customImageProcessing': defaultCustomImageProcessing,
    'sni': true,
    'autoAddLanguageFilter': 'none', // none, chinese, english, japanese
    'comicSourceListUrl': _defaultSourceListUrl,
    'preloadImageCount': 4,
    'followUpdatesFolder': null,
    'initialPage': '0',
    'comicListDisplayMode': 'paging', // paging, continuous
    'showPageNumberInReader': true,
    'showSingleImageOnFirstPage': false,
    'enableDoubleTapToZoom': true,
    'reverseChapterOrder': false,
    'showSystemStatusBar': false,
    'comicSpecificSettings': <String, Map<String, dynamic>>{},
    'deviceSpecificSettings': <String, Map<String, dynamic>>{},
    'deviceId': '',
    // ⭐ 重构（2026-10-10 用户方案 ✓）：两个「启用设备特定设置」开关 —— **纯标志** ✓，
    // 只表示"对应的键在本设备**不参与同步/备份/恢复**" ✓；默认关（= 与云端一致 ✓，零回归 ✓）。
    'deviceSpecificAppearanceEnabled': false,
    'deviceSpecificReaderEnabled': false,
    'ignoreBadCertificate': false,
    'readerScrollSpeed': 1.0, // 0.5 - 3.0
    'localFavoritesFirst': true,
    'autoCloseFavoritePanel': false,
    'showChapterComments': true, // show chapter comments in reader
    'showChapterCommentsAtEnd':
        false, // show chapter comments at end of chapter
    'commentFontSize': 16.0, // comment text font size, 12.0 - 24.0
    'autoFavoriteCover': true, // auto favorite cover when adding favorite
    'imageFavoritesDisplayType': 0, // 0=Tags, 1=Authors, 2=Comics
    'showImageFavoritesChart':
        true, // show chart in image favorites card on home page
    'showComments': true, // 评论区总开关：false 时全局不显示评论内容
    'backgroundColor': 'transparent', // 背景底色：'transparent' 或 '#RRGGBB'
    'backgroundImage': '', // 背景图片文件名（存于 dataPath/background/）
    'backgroundImageSource': '', // 原始选取路径（设置页显示"真实文件地址与文件名"）
    'backgroundImageOpacity': 1.0, // 背景图片透明度 0.0 - 1.0
    'backgroundImageFit':
        'cover', // cover/contain/fill/fitWidth/fitHeight/none/scaleDown/repeat
    'windowOverlayColor':
        'system', // 窗口/按钮背景色：system / transparent / #RRGGBB（独立于主题色）
    'windowOverlayOpacity': 1.0, // 窗口表面遮罩不透明度 0.0 - 1.0
    // ⭐ H3：**按钮背景**与「窗口背景」分离 ✓（原先按钮与面板同色 ✗ → 完全融合 ✗）。
    // `buttonOverlayColor` = `system` → **跟随系统容器色** ✓（M2 起不再跟随窗口色 ✗）；
    // `buttonOverlayOpacity` 默认 **0.85** ✓（与窗口默认 1.0 不同 → 默认就有层次 ✓）。
    // 另：`window_overlay.dart` 的 `buttonOverlayColor()` 保留"未设置时自动 +0.3"兜底 ✓（兼容旧配置 ✓）。
    'buttonOverlayColor': 'system',
    'buttonOverlayOpacity': 0.85,
    // ⭐ J1：**图标按钮**（只有图标的按钮 ✓）也有独立的颜色与不透明度 ✓ ——
    // `iconOverlayColor` = `system` → **跟随胶囊按钮色** ✓；`iconOverlayOpacity` 默认 0.85 ✓
    //（与胶囊默认一致 ✓ → 开箱零视觉变化 ✓，用户可各自调开 ✓）。
    'iconOverlayColor': 'system',
    'iconOverlayOpacity': 0.85,
    // ⭐ K1：**标签（tag/chip）背景**也独立 ✓ —— `tagOverlayColor` = `system` → 跟随**系统容器色** ✓
    //（与旧 tagColorMode=overlay 行为一致 ✓ 颜色零回归 ✓）；`tagOverlayOpacity` 默认 0.85 ✓
    //（与按钮/图标按钮一致 ✓）。仅当「标签颜色」= 跟随遮罩时生效 ✓（跟随主题时用 secondaryContainer ✓）。
    'tagOverlayColor': 'system',
    'tagOverlayOpacity': 0.85,
    // ⭐ AF1（用户要求 ✓）：顶栏「分类/发现页顶部**漫画源按钮**」（含「+ 加号」✓）独立控制 ✓：
    // `system` = 跟随**主题**（`secondaryContainer` ✓ = 现状外观 ✓ 零回归 ✓）/ `transparent` / `#RRGGBB` ✓；
    // 不透明度默认 **1** ✓（与现有观感一致 ✓）。仅「窗口与控件」总开关关闭（自定义 ✓）时生效 ✓。
    'sourceTabOverlayColor': 'system',
    'sourceTabOverlayOpacity': 1.0,
    // ⭐ AQ1（用户要求 ✓，2026-10-09）：**上下文菜单 / 一级弹出菜单**（`components/menu.dart` 那一族 ✓，
    // 如「…」按钮弹出的 重命名/重新排序/导出/… ✓）的**独立外观** ✓ —— 用户原话：
    // "现在这个纯透明状态**可视化非常差** ✗，可以做成和现有弹出式二级菜单一样的**可配置是否半透明**"✓。
    // ⭐ AR1（用户要求 ✓，2026-10-09 二次指示）：这三项**复刻二级页面弹窗**的同一套设计语言 ✓ ——
    // 用户原话："把菜单的样式和背景也**学习二级页面弹窗**的背景和样式**复刻上去**
    //（**透明/不透明，变暗/变浅**）"✓ → 故菜单用与二级页面**同名同义**的三个键 ✓
    //（`mode` 不透明/半透明/关闭 ✓、`tint` 变暗/变浅/无色调 ✓、`tintStrength` 强度 ✓），
    // 默认值与二级页面一致 ✓ → **默认观感与二级弹窗一致** ✓、开箱即可读 ✓。
    'menuSurfaceMode': 'opaque',
    // ⭐ AW2（用户 2026-10-09 指示 ✓）：**首装即可用** ✓ —— 外观的自定义项默认全部关闭 ✓，
    // 菜单在"系统主题"下的基础配置固定为：**样式 = 不透明（遮挡）** ✓、**背景 = 变浅** ✓、
    // **色调强度 = 0.22** ✓（用户原话："弹出式二级页面的菜单样式、菜单背景、色调强度，
    // 应在弹出式二级页面总开关关闭时，系统主题控制下，设置为 样式：不透明（遮挡）、背景：变浅、
    // 菜单色调强度 0.22"✓）。
    // ⚠️ 因此 `menuSurfaceTint` 的默认值由 `darken` **改为 `lighten`** ✗→✓（其余两项原已一致 ✓）。
    'menuSurfaceTint': 'lighten',
    'menuSurfaceTintStrength': AppOpacity.tintStrengthDefault,
    // ⭐ 2026-10-09（用户指示 ✓）：**侧滑窗口 / 侧边栏**独立一组外观项 ✓ ——
    // 范围 = `components/side_bar.dart` 的 `showSideBar` 各调用点（漫画页收藏/选择章节/评论页）
    // + 收藏页「文件夹选择」✓；结构与「二级页面」「菜单」那两套**同构** ✓。
    // 默认值 = 用户原话"默认就是之前跟随主题的默认状态"✓ ⇒ 不透明遮挡 / 变浅 / 0.22 ✓。
    'sideBarSurfaceMode':
        'opaque', // 侧边栏样式：opaque(不透明遮挡) / transparent(半透明) / off
    'sideBarSurfaceTint':
        'lighten', // 侧边栏背景：darken(变深) / lighten(变浅) / none(无色调)
    'sideBarSurfaceTintStrength':
        AppOpacity.tintStrengthDefault, // 强度 0.0 - 0.6
    // ⭐「变暗」**独立开关** ✓（用户："变不变暗你给他单独配置个开关"✓）。**不设默认值** ⇒ 保持既有行为
    //（`side_bar.dart` 原逻辑：有自定义背景时不变暗 ✓、否则 black54 ✓）；设 true/false 即强制开/关 ✓。
    'sideBarDim': false, // 侧边栏「变暗」：false(默认,不变暗) / true(变暗)
    // ⚠️ AQ1 范围收敛（用户 2026-10-09 追加说明 ✓）：**毛玻璃不做** ✗ ——
    // 用户原话："毛玻璃不做了，**和现在的外观设计有冲突** ✗，如果要加毛玻璃**以后再说** ✓。
    // 就做成和现在已有的**二级弹窗窗口配置一样**就行 ✓，**保留设计理念** ✓。"
    // → 因此**不引入** `menuSurfaceBlur` 设置项 ✓，本模块只做「底色 + 不透明度」两项 ✓
    //（与既有二级页面外观项同构 ✓，设计语言一致 ✓）。
    // ⭐ N1：「跟随系统主题」总开关 ✓ —— 每个外观子页一个 ✓（默认**开** ✓ = 软件最初那种
    // 没有任何自定义外观的干净默认 ✓）。开启时该页所有自定义项**隐藏且不生效** ✓；
    // 关闭后才参与渲染 ✓。三者全开 = 完全回到最初的默认外观 ✓。
    'windowOverlayFollowTheme': true, // 窗口与控件页（窗口/胶囊/图标按钮/标签遮罩）
    'textFollowTheme': true, // 文字页（颜色/字体/字号/阴影/发光）
    'secondaryPageFollowTheme': true, // 二级页面页（样式/背景/对比强度）
    'windowOverlayCorner': 'rounded', // 窗口/按钮背景圆角：rounded / square
    // ── 全局文字（与自定义背景搭配）──
    'globalTextColor': 'system', // system / transparent / #RRGGBB（system=跟随系统）
    'globalFontFamily': '', // 空 = 跟随系统；否则字体名
    'globalFontFile': '', // 自定义字体文件（ttf/otf，存 dataPath/fonts/）
    'globalFontSource': '', // 自定义字体的原始选取路径（设置页显示真实地址）
    'globalFontScale': 1.0, // 全局字号缩放 0.8 - 1.4
    'textShadowEnabled': false, // 文字阴影开关
    'textShadowColor': '#000000', // 阴影颜色
    'textShadowBlur': 2.0, // 阴影模糊 0 - 10
    'textShadowOffsetX': 0.0, // 阴影横向偏移 -4 - 4
    'textShadowOffsetY': 1.0, // 阴影纵向偏移 -4 - 4
    'textGlowEnabled': false, // 文字发光开关
    'textGlowColor': '#FFFFFF', // 发光颜色
    'textGlowRadius': 4.0, // 发光半径 0 - 20
    'textGlowStrength': 0.8, // 发光强度 0 - 1
    'secondaryPageTint': 'darken', // 二级页面区分：darken/lighten/none
    'secondaryPageTintStrength': 0.22, // 二级页面区分强度 0.0 - 0.6
    'secondaryPageMode': 'opaque', // 二级页面样式：opaque(不透明遮挡) / transparent(半透明)
    'secondaryMenuDim': true, // O1：首次打开即"突出二级菜单"（周围变暗 ✓），遮挡照旧 ✓
  };

  /// ① 背景体系：是否有背景图 / 背景底色（决定全局背景层、页面透明化、毛玻璃禁用）。
  bool get backgroundFeatureActive =>
      (this['backgroundImage'] as String? ?? '').isNotEmpty ||
      (this['backgroundColor'] as String? ?? 'transparent') != 'transparent';

  /// ②-a 是否需要**填充方块**（遮罩色不是「透明」即需要）。
  /// ⭐ N1：该页总开关「跟随系统主题」开启时 ✗ → 一律 false ✓（遮罩不参与 ✓，回到最初默认 ✓）。
  bool get hasWindowOverlay =>
      this['windowOverlayFollowTheme'] != true &&
      (this['windowOverlayColor'] ?? 'system').toString() != 'transparent';

  /// ②-b **圆角样式是否生效** —— ⭐ P1 修正（用户反馈 ✓）：**始终生效** ✓。
  /// 上一版让它在"跟随主题"时失效 ✗ → 胶囊按钮变成**直角方块** ✗（用户实测反馈 ✓）。
  /// 形状属于"主题默认"的一部分 ✓，不该被总开关关掉 ✓。
  bool get cornerStyleActive => true;

  /// ② 窗口与控件体系是否启用（填充 或 形状任一被配置）。
  bool get windowOverlayEnabled => hasWindowOverlay || cornerStyleActive;

  /// ③ 二级页面体系是否启用：**除显式选择「关闭(off)」外一律生效**。
  /// （旧逻辑用"偏离默认值"判定，导致 `不透明+加深+0.22` 这组默认值被判为未启用）
  /// ⭐ O1（用户澄清 ✓）：该页总开关「跟随系统主题」开启时 ✗ **仍然启用** ✓ ——
  /// 因为默认态必须**遮挡下面内容**（不透明面板 ✓）且**突出**（变暗 ✓）；
  /// "跟随主题"只让**色调调整**（tint/strength ✓）不生效 ✓，见 `customSecondarySurfaceColor` ✓。
  bool get secondaryPageFeatureActive =>
      (this['secondaryPageMode'] as String? ?? 'opaque') != 'off';

  /// 兼容旧调用：任一体系启用。
  bool get customBackgroundActive =>
      backgroundFeatureActive ||
      windowOverlayEnabled ||
      secondaryPageFeatureActive;

  /// 自定义背景底色的 ARGB 值（未设置/非法/透明时返回 null）。
  int? get customBackgroundBaseColorValue {
    final v = this['backgroundColor'] as String? ?? 'transparent';
    if (!v.startsWith('#') || v.length != 7) return null;
    final n = int.tryParse(v.substring(1), radix: 16);
    if (n == null) return null;
    return 0xFF000000 | n;
  }

  operator [](String key) {
    // ⭐⭐ 重构（2026-10-10 用户方案 ✓）：**只有一套值** —— 所有设置**始终**读写主表 `_data` ✓。
    // 背景 ✓：此前「启用设备特定设置」开关会让受保护键改读写 `deviceSpecificSettings[deviceId]`
    // 这个**第二层** ✗ ⇒ 两套值 ⇒ 一连串 bug（孤儿条目 ✓、空值遮住真值 ✓、关开关时读到空/被写空 ✓ …），
    // 补丁治不完 ✓（用户原话："**我不理解这个开关为什么要做成这个形式的**…**不能做成就是保持现在的设置，
    // 但是阻隔同步和备份吗**" ✓）。
    // 现在 ✓：开关退化为**纯标志** ✓（只表示"这些键在本设备不参与同步/备份/恢复" ✓）⇒
    // **切换开关不改变任何读写语义** ✓ ⇒ 背景等值**不可能**因为切开关而丢 ✓。
    return _data[key];
  }

  operator []=(String key, dynamic value) {
    _data[key] = value;
    if (key != "dataVersion") {
      notifyListeners();
    }
  }

  /// 对外暴露的「设置已变化」通知入口（`notifyListeners` 是 protected，外部无法直接调）。
  ///
  /// 供 `App.forceRebuild()` 的兼容 shim 使用：让依赖 [AppSettingsScope] 的控件
  /// 由框架**精准重建**，取代历史上的整树 `markNeedsBuild()` 遍历。
  void notifySettingsChanged() => notifyListeners();

  void setEnabledComicSpecificSettings(
    String comicId,
    String sourceKey,
    bool enabled,
  ) {
    setReaderSetting(comicId, sourceKey, "enabled", enabled);
  }

  bool isComicSpecificSettingsEnabled(String? comicId, String? sourceKey) {
    if (comicId == null || sourceKey == null) {
      return false;
    }
    return _data['comicSpecificSettings']["$comicId@$sourceKey"]?["enabled"] ==
        true;
  }

  dynamic getReaderSetting(String comicId, String sourceKey, String key) {
    if (isComicSpecificSettingsEnabled(comicId, sourceKey)) {
      var comicValue =
          _data['comicSpecificSettings']["$comicId@$sourceKey"]?[key];
      if (comicValue != null) {
        return comicValue;
      }
    }
    return getDeviceReaderSetting(key);
  }

  void setReaderSetting(
    String comicId,
    String sourceKey,
    String key,
    dynamic value,
  ) {
    (_data['comicSpecificSettings'] as Map<String, dynamic>).putIfAbsent(
      "$comicId@$sourceKey",
      () => <String, dynamic>{},
    )[key] = value;
    notifyListeners();
  }

  void resetComicReaderSettings(String key) {
    (_data['comicSpecificSettings'] as Map).remove(key);
    notifyListeners();
  }

  /// 「阅读」开关 ✓（⭐ 重构后同为**纯标志** ✓ —— 只影响"是否参与同步/备份/恢复" ✓，不再搬值 ✓）。
  void setEnabledDeviceSpecificSettings(bool enabled) {
    _data['deviceSpecificReaderEnabled'] = enabled;
    notifyListeners();
  }

  /// ⭐ 2026-10-10（用户要求 ✓）：**「外观」独立开关** ✗→✓ —— 外观随设备形态（横竖屏/窗口大小）差异明显，
  /// 而阅读习惯往往跨设备统一 ⇒ 两者应各自决定"是否按设备独立保存" ✓。
  ///
  /// ⭐⭐ 重构（2026-10-10 用户方案 ✓）：本开关现在是**纯标志** ✓ —— 只表示
  /// "外观类键在本设备**不参与同步 / 备份 / 恢复**" ✓，**不再**把值搬到第二层 ✗ ⇒ 翻转它不改任何值 ✓。
  void setEnabledAppearanceDeviceSettings(bool enabled) {
    _data['deviceSpecificAppearanceEnabled'] = enabled;
    notifyListeners();
  }

  bool isAppearanceDeviceSettingsEnabled() =>
      _data['deviceSpecificAppearanceEnabled'] == true;

  bool isDeviceSpecificSettingsEnabled() =>
      _data['deviceSpecificReaderEnabled'] == true;

  /// ⭐ 2026-10-10（用户要求 ✓）：**外观类设置键集合** —— 这些键由「外观」开关管，其余键由「阅读」开关管 ✓。
  static const _appearanceDeviceKeys = <String>{
    'color',
    'globalIconColor',
    'globalTextColor',
    'textShadowColor',
    'textGlowColor',
    'globalFontFile',
    'globalFontSource',
    'backgroundImage',
    'backgroundImageSource',
    'windowOverlayColor',
    'buttonOverlayColor',
    'iconOverlayColor',
    'tagOverlayColor',
    'sourceTabOverlayColor',
    'theme_mode',
    'comicDisplayMode',
    'comicTileScale',
    'comicListDisplayMode',
    'backgroundColor',
    'backgroundImageOpacity',
    'backgroundImageFit',
    'secondaryPageFollowTheme',
    'secondaryMenuDim',
    'secondaryPageMode',
    'secondaryPageTint',
    'secondaryPageTintStrength',
    'menuSurfaceMode',
    'menuSurfaceTint',
    'menuSurfaceTintStrength',
    'sideBarDim',
    'sideBarSurfaceMode',
    'sideBarSurfaceTint',
    'sideBarSurfaceTintStrength',
    'textFollowTheme',
    'globalFontFamily',
    'globalFontScale',
    'textShadowEnabled',
    'textShadowBlur',
    'textShadowOffsetX',
    'textShadowOffsetY',
    'textGlowEnabled',
    'textGlowRadius',
    'textGlowStrength',
    'windowOverlayFollowTheme',
    'windowOverlayOpacity',
    'buttonOverlayOpacity',
    'iconOverlayOpacity',
    'tagOverlayOpacity',
    'sourceTabOverlayOpacity',
    'windowOverlayCorner',
  };

  bool _isAppearanceDeviceKey(String key) =>
      _appearanceDeviceKeys.contains(key);

  /// ⭐ 2026-10-10（用户指正 ✓）：**阅读类设置键集合** —— 仅这些键归「阅读」开关管 ✓；
  /// 其余键（发现 / 本地收藏 / 应用 / 网络等页面的设置 ✓）**不受任何设备开关影响** ✓，照常参与同步 ✓。
  static const _readerDeviceKeys = <String>{
    'autoPageTurningInterval',
    'commentFontSize',
    'enableClockAndBatteryInfoInReader',
    'enableCustomImageProcessing',
    // ⭐ 补漏（2026-10-10 草稿回顾发现 ✓）：`customImageProcessing`（自定义图像处理脚本 ✓）
    // 也是**阅读类**设置 ✗→✓ —— 原先只在集合外的 `enableCustomImageProcessing`（开关 ✓）在集合内 ✓，
    // 而脚本内容本身漏了 ✗；它虽已在 `_disableSync`（从不参与同步 ✓）⇒ 无实际影响 ✓，但按"同类同管"补上更一致 ✓。
    'customImageProcessing',
    'enablePageAnimation',
    'enableTapToTurnPages',
    'longPressZoomPosition',
    'pageUpAndDownAction',
    'preloadImageCount',
    'quickCollectImage',
    'readerMode',
    'readerScreenPicNumberForLandscape',
    'readerScreenPicNumberForPortrait',
    'readerScrollSpeed',
    'reverseChapterOrder',
    'reverseTapToTurnPages',
    'showChapterComments',
    'showChapterCommentsAtEnd',
    'showPageNumberInReader',
    'showSingleImageOnFirstPage',
    'showSystemStatusBar',
    'enableDoubleTapToZoom',
    'enableLongPressToZoom',
    'enableTurnPageByVolumeKey',
    'limitImageWidth',
  };

  bool _isReaderDeviceKey(String key) => _readerDeviceKeys.contains(key);

  /// ⭐ 该键是否受「设备特定设置」保护 ✓（**三组**：外观键看外观开关 ✓、阅读键看阅读开关 ✓、其余一律 false ✓）。
  bool isDeviceProtected(String key) {
    if (_isAppearanceDeviceKey(key)) return isAppearanceDeviceSettingsEnabled();
    if (_isReaderDeviceKey(key)) return isDeviceSpecificSettingsEnabled();
    return false;
  }

  /// ⭐⭐ 重构（2026-10-10 用户方案 ✓）：**只有一套值** ⇒ 本方法与 `[]` 完全等价 ✓
  ///（保留方法名只为兼容既有调用点 ✓；"设备优先/回落全局"的双层语义**已删除** ✗）。
  dynamic getDeviceReaderSetting(String key) => _data[key];

  /// ⭐⭐ 重构（2026-10-10 用户方案 ✓）：写入**主表** ✓ —— 不再有第二层 ✗ ⇒
  /// 开关翻转/条目增删都不可能再让值"消失"或"被空值遮住" ✓（整类 bug 从根上消失 ✓）。
  void setDeviceReaderSetting(String key, dynamic value) {
    _data[key] = value;
    notifyListeners();
  }

  /// ⭐ 迁移（2026-10-10 用户方案 ✓）：把旧版**第二层**（`deviceSpecificSettings[deviceId]` ✓）
  /// 里的值**搬进主表** ✓，然后清空该表 ✓。
  ///
  /// 规则 ✓（**不丢老用户配置** ✓、**幂等** ✓）：
  /// ① ⭐ **权威条目**（2026-10-10 回归审查 P1-5 ✓）：**存在当前 `deviceId` 的条目时，只用它** ✗ ——
  ///    其余历史条目**完全不参与** ✓；只有当前条目**不存在**时才认领"**最后一条**"历史条目 ✓
  ///    （沿用 `f9c64ea` 的 `keys.last` 语义 ✓，不把多条目的开关 OR 起来 ✗ —— 否则"当前条开关关 +
  ///    孤儿条开关开"会**静默把开关打开** ✓ 并让孤儿过期值覆盖主表 ✗）；
  /// ② **开关标志**：由**权威条目**的 `enabledAppearance` / `enabled` 决定 ✓（true ⇒ 置位 ✓，缺省/false ⇒ 不置位 ✓）；
  /// ③ **设置值**：按**权威条目自己的旧开关**决定优先级 ✓ ——
  ///    · 旧开关**开着** ⇒ 它里面的非空值就是用户当时**实际看到**的值 ⇒ **覆盖主表** ✓；
  ///    · 开关**关着** ⇒ 主表值才是用户看到的 ✓ ⇒ 仅在主表为空时用其非空值**补齐** ✓；
  /// ④ **空值一律跳过** ✓（绝不用空值覆盖任何非空值 ✗）；
  /// ⑤ 处理完把 `deviceSpecificSettings` **清空** ✓ 并返回 true（调用方据此落盘一次 ✓）；
  ///    清空后再启动 ⇒ 该方法直接返回 false ✓ = **幂等** ✓。
  bool _migrateDeviceSpecificSettings() {
    final old = _data['deviceSpecificSettings'];
    if (old is! Map || old.isEmpty) return false;
    final deviceId = _data['deviceId'] as String? ?? '';
    // ① 选权威条目 ✓：当前 id 优先 ✓；没有才认领最后一条历史条目 ✓（其余条目不参与 ✗）。
    Map<dynamic, dynamic>? authoritative;
    if (deviceId.isNotEmpty && old[deviceId] is Map) {
      authoritative = old[deviceId] as Map;
    } else if (old.isNotEmpty) {
      final last = old[old.keys.last];
      if (last is Map) authoritative = last;
    }
    if (authoritative != null) {
      final appearanceOn = authoritative['enabledAppearance'] == true;
      final readerOn = authoritative['enabled'] == true;
      if (appearanceOn) _data['deviceSpecificAppearanceEnabled'] = true;
      if (readerOn) _data['deviceSpecificReaderEnabled'] = true;
      for (final e in authoritative.entries) {
        final key = e.key.toString();
        if (key == 'enabled' || key == 'enabledAppearance') continue;
        final value = e.value;
        if (value == null || (value is String && value.isEmpty)) continue;
        final current = _data[key];
        final currentIsEmpty =
            current == null || (current is String && current.isEmpty);
        final keyIsAppearance = _isAppearanceDeviceKey(key);
        final keyIsReader = _isReaderDeviceKey(key);
        final deviceWins =
            (keyIsAppearance && appearanceOn) || (keyIsReader && readerOn);
        if (deviceWins || currentIsEmpty) {
          _data[key] = value;
        }
      }
    }
    _data['deviceSpecificSettings'] = <String, dynamic>{};
    return true;
  }

  /// ⭐ 2026-10-10 用户方案 ✓：**本按钮不再清值** ✗→✓ ——
  /// 新语义下"清除本设备的特殊设置" = **关闭两个开关** ✓（这些键重新参与同步/备份/恢复 ✓），
  /// **值一概不动** ✓（用户此前看到"清除后开关自动关闭" ✓ ⇒ 新语义下**只有开关会关** ✓，值全部保留 ✓）。
  void resetDeviceSpecificSettings() => resetDeviceReaderSettings();

  void resetDeviceReaderSettings() {
    _data['deviceSpecificAppearanceEnabled'] = false;
    _data['deviceSpecificReaderEnabled'] = false;
    // 旧版残留的第二层一并清掉 ✓（值已在启动时迁移进主表 ✓，此处只清空壳 ✓）。
    _data['deviceSpecificSettings'] = <String, dynamic>{};
    notifyListeners();
  }

  /// 读取设置值的**三级优先级唯一入口**：漫画专属 → 设备专属 → 全局。
  ///
  /// 设置组件（`_SwitchSetting` / `_SliderSetting` / `SelectSetting` 系）此前各自
  /// 内联这段三分支判定，现收口于此，避免同一逻辑散落多处。
  dynamic readSettingValue({
    required String key,
    String? comicId,
    String? comicSource,
    bool useDeviceSettings = false,
  }) {
    if (comicId != null) {
      return getReaderSetting(comicId, comicSource!, key);
    }
    if (useDeviceSettings) {
      return getDeviceReaderSetting(key);
    }
    return this[key];
  }

  /// 写入设置值（与 [readSettingValue] 对称的三级优先级）。
  void writeSettingValue({
    required String key,
    required dynamic value,
    String? comicId,
    String? comicSource,
    bool useDeviceSettings = false,
  }) {
    if (comicId != null) {
      setReaderSetting(comicId, comicSource!, key, value);
    } else if (useDeviceSettings) {
      setDeviceReaderSetting(key, value);
    } else {
      this[key] = value;
    }
  }

  // ⭐ 重构（2026-10-10 用户方案 ✓）：`_getOrCreateDeviceId()` 已**删除** ✗ ——
  // 新语义下不再有"按 deviceId 分键的第二层" ✓（`deviceId` 仍由 `doInit` 生成并保留，
  // 供同步排除清单与历史数据识别 ✓），所以这里不再需要它 ✓。

  @override
  String toString() {
    return _data.toString();
  }
}

const defaultCustomImageProcessing = '''
/**
 * Process an image
 * @param image {ArrayBuffer} - The image to process
 * @param cid {string} - The comic ID
 * @param eid {string} - The episode ID
 * @param page {number} - The page number
 * @param sourceKey {string} - The source key
 * @returns {Promise<ArrayBuffer> | {image: Promise<ArrayBuffer>, onCancel: () => void}} - The processed image
 */
async function processImage(image, cid, eid, page, sourceKey) {
    let futureImage = new Promise((resolve, reject) => {
        resolve(image);
    });
    return futureImage;
}
''';

const defaultSourceListUrl =
    "https://cdn.jsdelivr.net/gh/opaiopaio/venera-configs@main/index.json";

/// 保留私有别名以保持向后兼容。
const _defaultSourceListUrl = defaultSourceListUrl;

/// 旧版漫画源列表 URL 集合。init.dart 在启动时用于一次性迁移:
/// 将使用这些 URL 的用户切回 [_defaultSourceListUrl]。
/// 迁移通过本地标志位保证只执行一次,用户之后手动改回的 URL 不会被再次覆盖。
const legacySourceListUrls = <String>{
  "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json",
  "https://cdn.jsdelivr.net/gh/haukuen/venera-configs@main/index.json",
};
