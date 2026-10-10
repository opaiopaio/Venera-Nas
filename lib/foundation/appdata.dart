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

      var disableSyncFields = json["settings"]["disableSyncFields"] as String;
      if (disableSyncFields.isNotEmpty) {
        var json4sync = jsonDecode(data);
        List<String> customDisableSync = splitField(disableSyncFields);
        for (var field in customDisableSync) {
          json4sync["settings"].remove(field);
        }
        var data4sync = jsonEncode(json4sync);
        var file4sync = File(FilePath.join(App.dataPath, 'syncdata.json'));
        futures.add(file4sync.writeAsString(data4sync));
      }

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
  ];

  /// Restore data from a local backup file.
  /// Unlike [syncData], this restores most settings including webdav config.
  void restoreFromBackup(Map<String, dynamic> data) {
    if (data['settings'] is Map) {
      var settings = data['settings'] as Map<String, dynamic>;
      for (var key in settings.keys) {
        if (!_disableRestore.contains(key) && settings[key] != null) {
          this.settings[key] = settings[key];
        }
      }
    }
    searchHistory = List.from(data['searchHistory'] ?? []);
    saveData();
  }

  /// Following fields are related to device-specific data and should not be synced.
  static const _disableSync = [
    // ⭐ 修复（2026-10-09 用户指示 ✓）：**背景信息与背景设置不参与同步** ✗ ——
    // 用户原话："同步不要同步背景信息，背景的设置也不要同步，不然两个客户端背景不一致他就会给你换成白底"✓。
    // 原因 ✓：另一端没有同名背景图文件 ⇒ 同步过来的路径无效 ⇒ 该端退化成白底 ✓。
    "backgroundImage",
    "backgroundColor",
    "backgroundImageOpacity",
    "backgroundImageFit",
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
            this.settings[key] = settings[key];
          }
          continue;
        }
        if (!_disableSync.contains(key) && !customDisableSync.contains(key)) {
          this.settings[key] = settings[key];
        }
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
    // ⭐ 修复（2026-10-10 用户要求 ✓）：**读取改为"按设备优先"** ✗→✓ ——
    // 原先恒返回 `_data[key]` ✗ ⇒ 即便启用了「设备特定设置」✗，全仓 323 处消费端（主题 / 亮度 / 背景 / 覆盖物等）
    // 读到的仍是**同步来的全局值** ✗ ⇒ 开关只存不读、等于失效 ✓。
    // 现改走 `getDeviceReaderSetting(key)` ✓：**未启用时直接回退 `_data[key]`** ✓ ⇒ 默认路径行为逐字不变 ✓（零回归 ✓）；
    // 启用后本设备改过的值优先 ✓，而 `[]=`（同步写入）仍只写全局 ✓ ⇒ **同步更新全局、本设备保留自己的配置** ✓。
    return getDeviceReaderSetting(key);
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

  void setEnabledDeviceSpecificSettings(bool enabled) {
    setDeviceReaderSetting("enabled", enabled);
  }

  bool isDeviceSpecificSettingsEnabled() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isEmpty) {
      return false;
    }
    return _data['deviceSpecificSettings'][deviceId]?["enabled"] == true;
  }

  dynamic getDeviceReaderSetting(String key) {
    if (!isDeviceSpecificSettingsEnabled()) {
      return _data[key];
    }
    var deviceId = _data['deviceId'] as String;
    return _data['deviceSpecificSettings'][deviceId]?[key] ?? _data[key];
  }

  void setDeviceReaderSetting(String key, dynamic value) {
    var deviceId = _getOrCreateDeviceId();
    (_data['deviceSpecificSettings'] as Map<String, dynamic>).putIfAbsent(
      deviceId,
      () => <String, dynamic>{},
    )[key] = value;
    notifyListeners();
  }

  void resetDeviceReaderSettings() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isEmpty) {
      return;
    }
    (_data['deviceSpecificSettings'] as Map).remove(deviceId);
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

  String _getOrCreateDeviceId() {
    var deviceId = _data['deviceId'] as String;
    if (deviceId.isNotEmpty) {
      return deviceId;
    }
    var id = const Uuid().v4();
    _data['deviceId'] = id;
    return id;
  }

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
