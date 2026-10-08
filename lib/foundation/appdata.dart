import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:venera_nas/foundation/app.dart';
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
    // `buttonOverlayColor` = `system` → **跟随窗口色** ✓（颜色零回归 ✓）；
    // `buttonOverlayOpacity` 默认 **0.85** ✓（与窗口默认 1.0 不同 → 默认就有层次 ✓）。
    // 另：`window_overlay.dart` 的 `buttonOverlayColor()` 保留"未设置时自动 +0.3"兜底 ✓（兼容旧配置 ✓）。
    'buttonOverlayColor': 'system',
    'buttonOverlayOpacity': 0.85,
    // ⭐ J1：**图标按钮**（只有图标的按钮 ✓）也有独立的颜色与不透明度 ✓ ——
    // `iconOverlayColor` = `system` → **跟随胶囊按钮色** ✓；`iconOverlayOpacity` 默认 0.85 ✓
    //（与胶囊默认一致 ✓ → 开箱零视觉变化 ✓，用户可各自调开 ✓）。
    'iconOverlayColor': 'system',
    'iconOverlayOpacity': 0.85,
    // ⭐ K1：**标签（tag/chip）背景**也独立 ✓ —— `tagOverlayColor` = `system` → 跟随**窗口**色 ✓
    //（与旧 tagColorMode=overlay 行为一致 ✓ 颜色零回归 ✓）；`tagOverlayOpacity` 默认 0.85 ✓
    //（与按钮/图标按钮一致 ✓）。仅当「标签颜色」= 跟随遮罩时生效 ✓（跟随主题时用 secondaryContainer ✓）。
    'tagOverlayColor': 'system',
    'tagOverlayOpacity': 0.85,
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
  };

  /// ① 背景体系：是否有背景图 / 背景底色（决定全局背景层、页面透明化、毛玻璃禁用）。
  bool get backgroundFeatureActive =>
      (this['backgroundImage'] as String? ?? '').isNotEmpty ||
      (this['backgroundColor'] as String? ?? 'transparent') != 'transparent';

  /// ②-a 是否需要**填充方块**（遮罩色不是「透明」即需要）。
  bool get hasWindowOverlay =>
      (this['windowOverlayColor'] ?? 'system').toString() != 'transparent';

  /// ②-b **圆角样式是否生效** —— 一套系统，始终生效。
  bool get cornerStyleActive => true;

  /// ② 窗口与控件体系是否启用（填充 或 形状任一被配置）。
  bool get windowOverlayEnabled => hasWindowOverlay || cornerStyleActive;

  /// ③ 二级页面体系是否启用：**除显式选择「关闭(off)」外一律生效**。
  /// （旧逻辑用"偏离默认值"判定，导致 `不透明+加深+0.22` 这组默认值被判为未启用）
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
