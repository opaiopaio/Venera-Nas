import 'dart:async';

import 'package:display_mode/display_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:rhttp/rhttp.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/cookie_jar.dart';
import 'package:venera_nas/pages/comic_source_page.dart';
import 'package:venera_nas/pages/follow_updates_page.dart';
import 'package:venera_nas/pages/settings/settings_page.dart';
import 'package:venera_nas/utils/app_links.dart';
import 'package:venera_nas/utils/auth_storage.dart';
import 'package:venera_nas/utils/handle_text_share.dart';
import 'package:venera_nas/utils/opencc.dart';
import 'package:venera_nas/utils/tags_translation.dart';
import 'package:venera_nas/utils/translations.dart';
import 'foundation/appdata.dart';

extension _FutureInit<T> on Future<T> {
  /// Prevent unhandled exception
  ///
  /// A unhandled exception occurred in init() will cause the app to crash.
  Future<void> wait() async {
    try {
      await this;
    } catch (e, s) {
      Log.error("init", "$e\n$s");
    }
  }
}

Future<void> init() async {
  await App.init().wait();
  await SingleInstanceCookieJar.createInstance();
  try {
    var futures = [
      Rhttp.init(),
      App.initComponents(),
      SAFTaskWorker().init().wait(),
      AppTranslation.init().wait(),
      TagsTranslation.readData().wait(),
      JsEngine().init().wait(),
      ComicSourceManager().init().wait(),
      OpenCC.init(),
      AuthStorage.init(),
    ];
    await Future.wait(futures);
  } catch (e, s) {
    Log.error("init", "$e\n$s");
  }
  CacheManager().setLimitSize(appdata.settings['cacheSize']);
  _checkOldConfigs();
  if (App.isAndroid) {
    handleTextShare();
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      Log.error("Display Mode", "Failed to set high refresh rate: $e");
    }
  }
  if (App.isMobile) {
    handleLinks();
  }
  FlutterError.onError = (details) {
    Log.error("Unhandled Exception", "${details.exception}\n${details.stack}");
  };
  if (App.isWindows) {
    // Report to the monitor thread that the app is running
    // https://github.com/venera-app/venera/issues/343
    Timer.periodic(const Duration(seconds: 1), (_) {
      const methodChannel = MethodChannel('venera/method_channel');
      methodChannel.invokeMethod("heartBeat");
    });
  }
}

void _checkOldConfigs() {
  if (appdata.settings['searchSources'] == null) {
    appdata.settings['searchSources'] = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
  }

  if (appdata.implicitData['webdavAutoSync'] == null) {
    var webdavConfig = appdata.settings['webdav'];
    if (webdavConfig is List &&
        webdavConfig.length == 3 &&
        webdavConfig.whereType<String>().length == 3) {
      appdata.implicitData['webdavAutoSync'] = true;
    } else {
      appdata.implicitData['webdavAutoSync'] = false;
    }
    appdata.writeImplicitData();
  }

  // 一次性迁移:把使用旧版源列表 URL 的用户切回当前默认值。
  // 通过本地标志位保证只执行一次 —— 用户之后手动改回的 URL 不会被再次覆盖。
  // 注意:每次 defaultSourceListUrl 变更时必须用新 key(旧版已置位旧 key,沿用会跳过迁移)。
  // 本次 1.7.1: default 由 haukuen/venera-configs 迁移至 opaiopaio/venera-configs。
  if (appdata.implicitData['sourceListMigratedToOpaiopaioRepo'] != true) {
    var currentUrl = appdata.settings['comicSourceListUrl'].toString();
    if (legacySourceListUrls.contains(currentUrl) ||
        currentUrl.contains("git.nyne.dev")) {
      appdata.settings['comicSourceListUrl'] = defaultSourceListUrl;
      appdata.saveData();
    }
    appdata.implicitData['sourceListMigratedToOpaiopaioRepo'] = true;
    appdata.writeImplicitData();
  }
}

Future<void> _checkAppUpdates() async {
  var lastCheck = appdata.implicitData['lastCheckUpdate'] ?? 0;
  var now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastCheck < 24 * 60 * 60 * 1000) {
    return;
  }
  appdata.implicitData['lastCheckUpdate'] = now;
  appdata.writeImplicitData();
  ComicSourcePage.checkComicSourceUpdate();
  if (appdata.settings['checkUpdateOnStart']) {
    await checkUpdateUi(false, true);
  }
}

void checkUpdates() {
  _checkAppUpdates();
  FollowUpdatesService.initChecker();
}


