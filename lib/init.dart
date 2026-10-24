import 'dart:async';

import 'package:display_mode/display_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:rhttp/rhttp.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/cookie_jar.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';
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
  // ⭐ 2026-10-25（用户要求 ✓，方案 A ✓）：**启动后预热阅读会话** ✓ ——
  // 用户会"启动就连、常驻、退出断开"✓；预热后**点漫画即用** ✓（否则第一次点要等 2~3 秒握手 ✗）。
  // 延迟 1.2 秒再连 ✓：不抢启动关键路径 ✓；失败记 **warning** 并**按服务器退避 24h** ✓
  //（真正点漫画时会立即重连并给出明确报错 ✓）。
  unawaited(_prewarmSmbReaderSessions());
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

/// 预热失败的**按服务器退避**时长 ✓ —— 同一共享 24 小时内不再自动预热 ✓。
///
/// 为什么需要（P2 ✓）：密码错 / 服务器离线时，原实现**每次启动**都会静默重试一遍 ✗
/// （启动后平白多一轮连接超时 ✓，NAS 上也会留下失败连接记录 ✓）。
/// 注意退避**只作用于"预热"** ✓：用户真正点开漫画时照旧立即重连并给出明确报错 ✓。
const Duration _smbPrewarmBackoff = Duration(hours: 24);

/// `implicitData` 里记录"各服务器最近一次预热失败时间"的键 ✓（服务器键 → epoch 毫秒 ✓）。
///
/// 服务器键取 `SmbConfig.cacheKey`（`host|port|share` ✓，**不含凭据** ✓，可安全落盘 ✓）。
/// 键名沿用 `implicitData` 既有的 camelCase 规范 ✓（与 `lastCheckUpdate` 同类 ✓）。
/// ⚠️ 兼容处理 ✓：旧版 `implicitData.json` 没有该键 ⇒ 视为"无失败记录" ✓；
/// 值类型不对（历史损坏 / 手工编辑 ✓）⇒ 逐项丢弃 ✓，绝不让预热因脏数据崩溃 ✗；
/// 已从设置里删掉的服务器记录会被顺带清理 ✓（避免该键无限长大 ✗）。
const String _smbPrewarmFailedAtKey = 'smbPrewarmFailedAt';

/// 读出预热失败记录 ✓（容错规则见 [_smbPrewarmFailedAtKey] ✓）。
Map<String, int> _readSmbPrewarmFailures() {
  final raw = appdata.implicitData[_smbPrewarmFailedAtKey];
  if (raw is! Map) return {};
  final result = <String, int>{};
  raw.forEach((key, value) {
    if (key is String && value is int && value > 0) {
      result[key] = value;
    }
  });
  return result;
}

/// 写回预热失败记录 ✓；空表时**删掉该键** ✓（不留空字段 ✓）。
Future<void> _writeSmbPrewarmFailures(Map<String, int> failures) async {
  if (failures.isEmpty) {
    appdata.implicitData.remove(_smbPrewarmFailedAtKey);
  } else {
    appdata.implicitData[_smbPrewarmFailedAtKey] = failures;
  }
  await appdata.writeImplicitData();
}

/// ⭐ 2026-10-25（用户要求 ✓，方案 A ✓）：**预热阅读专用 SMB 会话** ✓
///
/// 用户要的语义 ✓：启动即连、常驻、退出断开 ✓。
/// 启动 1.2 秒后为已保存的服务器各建一条**阅读会话** ✓
/// ⇒ 点漫画时**直接可用** ✓（不必再等 2~3 秒握手 ✗）。
/// 失败记 **warning** ✓ 并按服务器退避 24h ✓（见 [_smbPrewarmBackoff] ✓）：
/// 真正打开漫画时会再连并给出明确报错 ✓。
Future<void> _prewarmSmbReaderSessions() async {
  // ⭐ 2026-10-26：改用**启动预算令牌** ✓ —— 原先借用 `AppMotion.long * 3` 当网络延迟 ✗
  //（改个转场时长就会顺带改预热时机 ✓，语义不成立 ✗）。理由见 `design_tokens.dart` ✓。
  await Future.delayed(AppStartup.smbPrewarmDelay);
  final raw = appdata.settings['smbServers'];
  // ⭐ 2026-10-25：**打点（便于确认是否真的执行/读到几条服务器 ✓）** ✓
  Log.info(
    'SMB Connect',
    'prewarm start: serverCount=${raw is List ? raw.length : -1}',
  );
  if (raw is! List) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  final failures = _readSmbPrewarmFailures();
  // 只有记录真的变了才写盘 ✓（避免每次启动都白写一次 `implicitData.json` ✗）。
  var backoffChanged = false;
  // 本轮仍配置着的服务器 ✓ —— 已删除的服务器记录一并清掉 ✓（见 [_smbPrewarmFailedAtKey] ✓）。
  final alive = <String>{};

  for (final item in raw) {
    if (item is! Map) continue;
    SmbConnection conn;
    try {
      conn = SmbConnection.fromJson(Map<String, dynamic>.from(item));
    } catch (e) {
      Log.warning('SMB Connect', 'prewarm skipped invalid server config: $e');
      continue;
    }
    final cfg = conn.config;
    if (cfg.host.isEmpty || cfg.share.isEmpty) continue;
    // ⚠️ `cacheKey` **不含凭据** ✓（可安全写进日志 / implicitData ✓）。
    final key = cfg.cacheKey;
    alive.add(key);

    final failedAt = failures[key];
    if (failedAt != null) {
      final age = now - failedAt;
      // 仍在退避窗口内 ⇒ 跳过本次预热 ✓。
      // ⚠️ `age < 0`（时钟回拨 / 时间戳在未来 ✓）不当作退避 ✓ —— 否则该服务器会被**永久跳过** ✗。
      if (age >= 0 && age < _smbPrewarmBackoff.inMilliseconds) {
        final leftHours = ((_smbPrewarmBackoff.inMilliseconds - age) / 3600000)
            .ceil();
        Log.info(
          'SMB Connect',
          'prewarm skipped (backoff ${leftHours}h): ${cfg.host}/${cfg.share}',
        );
        continue;
      }
      // 退避已过期 ⇒ 清掉记录，给这次预热一个机会 ✓。
      failures.remove(key);
      backoffChanged = true;
    }

    try {
      await SmbClient.readerShared(cfg).connect(high: false);
      Log.info(
        'SMB Connect',
        'prewarmed reader session: ${cfg.host}/${cfg.share}',
      );
      if (failures.remove(key) != null) backoffChanged = true;
    } catch (e) {
      // ⚠️ 失败改 **warning** ✓（原为 info ✓）：密码错 / 服务器离线是**需要用户处理**的问题 ✗，
      // 不该沉在 info 里 ✓；同时按服务器记下时间 ✓ ⇒ 24h 内不再反复打扰 ✓。
      failures[key] = DateTime.now().millisecondsSinceEpoch;
      backoffChanged = true;
      Log.warning(
        'SMB Connect',
        'prewarm failed (retry after ${_smbPrewarmBackoff.inHours}h): '
            '${cfg.host}/${cfg.share}: $e',
      );
    }
  }

  final beforePrune = failures.length;
  failures.removeWhere((key, _) => !alive.contains(key));
  if (failures.length != beforePrune) backoffChanged = true;

  if (backoffChanged) {
    try {
      await _writeSmbPrewarmFailures(failures);
    } catch (e) {
      // 退避记录写失败不能反噬启动 ✓（下次仍会正常预热 ✓）。
      Log.warning('SMB Connect', 'prewarm backoff save failed: $e');
    }
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
