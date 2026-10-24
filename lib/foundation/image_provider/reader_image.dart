import 'dart:async' show Completer, Future, Timer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_serial.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'reader_image.dart' as image_provider;

/// ⭐ 2026-10-24：**SMB 原生操作的全局串行闸门** ✓
///
/// 崩溃实证（Windows 事件日志 ✓）：`libsmb2.dll` 报 **0xc0000005 访问冲突** ✗ ——
/// 原生库不能被"同一连接并发使用"或"读到一半被 disconnect" ✗。
/// 所以所有 SMB 操作必须**一次只做一件** ✓；本闸门让**前台请求优先** ✓、预取等不到就丢 ✓。
class _SmbGate {
  bool _locked = false;

  /// 当前持锁方的开始时间 ✓ —— 用于**看门狗**：异常情况下锁被卡死时强制复位 ✓（否则用户只能重启 App ✗）。
  DateTime? _lockedAt;

  final List<Completer<bool>> _high = [];

  final List<Completer<bool>> _low = [];

  bool get locked => _locked;

  /// 持锁超过 [limit] ⇒ 判定卡死 ✓（由调用方决定是否 [reset] ✓）。
  bool hasBeenLockedFor(Duration limit) {
    final at = _lockedAt;
    return _locked && at != null && DateTime.now().difference(at) > limit;
  }

  /// ⚠️ 强制复位 ✓：把锁与所有等待者都放掉 ✓（等待者按"失败"返回 ⇒ 走可重试错误 ✓）。
  ///
  /// 只在看门狗判定卡死时调用 ✓ —— 这是"不重启 App 也能恢复"的唯一兜底 ✓。
  void reset() {
    _locked = false;
    _lockedAt = null;
    final waiters = [..._high, ..._low];
    _high.clear();
    _low.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete(false);
      }
    }
  }

  /// ⭐ 2026-10-24（复查修复 ✓）：**超时判定必须用 Timer + `isCompleted` 互斥** ✓。
  ///
  /// 原先用 `c.future.timeout(...)` ✗ ⇒ 存在竞态：超时返回 false 的同时 `release()` 刚好把名额
  /// 给了我们 ✓ ⇒ 我们按"超时"走了 ✓ 但名额已被"移交" ✓ ⇒ **锁永久 locked** ✗（复查报告最担心的一条 ✓）。
  /// 现在：超时由 Timer 在 `isCompleted == false` 时**先移出队列再 complete(false)** ✓，
  /// 与 `release()` 在**同一事件循环**里互斥 ✓ ⇒ 名额不会丢 ✓。
  Future<bool> acquire({required bool high, Duration? timeout}) async {
    if (!_locked) {
      _locked = true;
      _lockedAt = DateTime.now();
      return true;
    }
    final c = Completer<bool>();
    final queue = high ? _high : _low;
    queue.add(c);
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!c.isCompleted) {
          queue.remove(c);
          c.complete(false);
        }
      });
    }
    final granted = await c.future;
    timer?.cancel();
    return granted;
  }

  void release() {
    if (_high.isNotEmpty) {
      _high.removeAt(0).complete(true);
      _lockedAt = DateTime.now();
      return;
    }
    if (_low.isNotEmpty) {
      _low.removeAt(0).complete(true);
      _lockedAt = DateTime.now();
      return;
    }
    _locked = false;
    _lockedAt = null;
  }
}

class ReaderImageProvider
    extends BaseImageProvider<image_provider.ReaderImageProvider> {
  /// Image provider for normal image.
  const ReaderImageProvider(
    this.imageKey,
    this.sourceKey,
    this.cid,
    this.eid,
    this.page, {
    this.enableResize = false,
    this.onLoadFailed,
    this.lowPriority = false,
  });

  final String imageKey;

  final String? sourceKey;

  final String cid;

  final String eid;

  final int page;

  final void Function()? onLoadFailed;

  /// ⭐ 复查修复（2026-10-24）：**低优先级** ✓（预解码/预取用 ✓）——
  /// 让这类 SMB 读取去抢**预取名額**（low ✓）而不是前台名额（high ✗），
  /// 否则 3 个预解码请求就能把前台的 15s 预算吃光 ⇒ 当前页反而报 "SMB read busy." ✗。
  final bool lowPriority;

  @override
  final bool enableResize;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    Uint8List? imageBytes;
    if (imageKey.startsWith('file://')) {
      var file = File(imageKey.substring(7));
      if (await file.exists()) {
        imageBytes = await file.readAsBytes();
      } else {
        throw "Error: File not found.";
      }
    } else if (imageKey.startsWith('smb://')) {
      // ⭐ 修复（2026-10-24）：SMB 页改为「先查磁盘缓存 → 未命中才读 → 读到落盘」。
      // 原因：原先 SMB 页每次现读现解码、且**不写盘**，翻页回到已读页要重新走网络，
      // 夜间网络慢时表现为持续闪烁。落盘后同一页只拉一次。
      // 失败日志由 _readSmbPage 内部打（判停异常不打，避免快速翻页时刷屏）。
      Log.info('SMB Reader', 'loading: $imageKey');
      imageBytes = await _readSmbPage(
        imageKey,
        cacheKey,
        checkStop,
        foreground: !lowPriority,
      );
    } else {
      await for (var event in ImageDownloader.loadComicImage(
        imageKey,
        sourceKey,
        cid,
        eid,
      )) {
        checkStop();
        chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: event.currentBytes,
            expectedTotalBytes: event.totalBytes,
          ),
        );
        if (event.imageBytes != null) {
          imageBytes = event.imageBytes;
          break;
        }
      }
    }
    if (imageBytes == null) {
      throw "Error: Empty response body.";
    }
    if (appdata.settings['enableCustomImageProcessing']) {
      var script = appdata.settings['customImageProcessing'].toString();
      if (!script.contains('function processImage')) {
        return imageBytes;
      }
      var func = JsEngine().runCode('''
        (() => {
          $script
          return processImage;
        })()
      ''');
      if (func is JSInvokable) {
        var autoFreeFunc = JSAutoFreeFunction(func);
        var result = autoFreeFunc([imageBytes, cid, eid, page, sourceKey]);
        if (result is Uint8List) {
          imageBytes = result;
        } else if (result is Future) {
          var futureResult = await result;
          if (futureResult is Uint8List) {
            imageBytes = futureResult;
          }
        } else if (result is Map) {
          var image = result['image'];
          if (image is Uint8List) {
            imageBytes = image;
          } else if (image is Future) {
            JSAutoFreeFunction? onCancel;
            if (result['onCancel'] is JSInvokable) {
              onCancel = JSAutoFreeFunction(result['onCancel']);
            }
            if (onCancel == null) {
              var futureImage = await image;
              if (futureImage is Uint8List) {
                imageBytes = futureImage;
              }
            } else {
              dynamic futureImage;
              image.then((value) {
                futureImage = value;
                futureImage ??= Uint8List(0);
              });
              while (futureImage == null) {
                try {
                  checkStop();
                } catch (e) {
                  onCancel([]);
                  rethrow;
                }
                await Future.delayed(Duration(milliseconds: 50));
              }
              if (futureImage is Uint8List) {
                imageBytes = futureImage;
              }
            }
          }
        }
      }
    }
    return imageBytes!;
  }

  /// ⭐ 2026-10-24（第四次修订 ✗→✓）：**SMB 操作全局串行化 + 绝不在读到一半时断开连接** ✓
  ///
  /// 崩溃实证 ✓：`libsmb2.dll` 抛 **0xc0000005 访问冲突** ✗（原生层 ✓，非 Dart 异常 ✓）——
  /// 原生库在**并发使用同一连接** / **读到一半被 disconnect** 时会崩 ✓。
  /// 对策 = ⭐ 所有 connect / readFile / disconnect **串行** ✓（[_smbGate] ✓），
  /// 且**只有 `_activeReads == 0` 时才真正断开** ✓（否则标记稍后断开 ✓）。
  static final _smbGate = _SmbGate();

  /// 在途的 SMB **原生读**计数 ✓ —— 只有为 0 才允许 disconnect ✓（防 use-after-free ✓）。
  static int _activeReads = 0;

  /// "稍后断开"标记 ✓ —— 等最后一个在途读结束后再断开 ✓。
  static bool _closeSharedRequested = false;

  /// 前台读图最近一次开始的毫秒时间戳 ✓ —— 预取据此判断"用户正在翻页 ⇒ 丢弃预取" ✓。
  static int _lastForegroundReadAt = 0;

  /// 前台等待上限 ✓（超过才报可重试错误 ✓，不无限转圈 ✓）。
  static const _smbForegroundWaitTimeout = Duration(seconds: 15);

  /// 预取排队超时 ✓。
  static const _smbPrefetchWaitTimeout = Duration(seconds: 3);

  /// 复用连接的**空闲断开**时长 ✓（避免在 NAS 上挂长期空闲会话 ✓）。
  static const _smbIdleDisconnect = Duration(seconds: 60);

  /// ⭐ 闸门看门狗时长 ✓（复查修复 2026-10-24）：锁被异常卡死超过此时长 ⇒ **强制复位** ✓，
  /// 避免"每页转圈 ~59s 后报错、只能重启 App" ✗。
  static const _smbGateWatchdog = Duration(seconds: 90);

  /// 同一页**在途读取去重** ✓：`load` 与预取可能同时触发同一页 ✗ ⇒ 共用一个 Future ✓。
  static final Map<String, Future<Uint8List>> _inflightReads = {};

  /// SMB 页磁盘缓存有效期：7 天（漫画页不会变，长有效期才能让"回头翻"命中）。
  static const _smbPageCacheDuration = 7 * 24 * 60 * 60 * 1000;

  /// ⭐ 复用的 SMB 连接 ✓（整段阅读共用一条 ✓；退出阅读器时由 [closeSharedSmbClient] 断开 ✓）。
  static SmbClient? _sharedClient;

  static String? _sharedClientKey;

  static DateTime? _sharedClientLastUsed;

  /// 取得（必要时建立）复用的 SMB 连接 ✓。
  ///
  /// [high] = true 表示"用户在等"（当前页 ✓）—— 会优先于后台任务拿到全局 SMB 闸门 ✓。
  static Future<SmbClient> _obtainClient(
    SmbConfig config, {
    bool high = false,
  }) async {
    final key =
        '${config.host}|${config.port}|${config.share}|'
        '${config.username}|${config.password.hashCode}|${config.domain}';
    final existing = _sharedClient;
    if (existing != null && _sharedClientKey == key && existing.isConnected) {
      final last = _sharedClientLastUsed;
      if (last == null ||
          DateTime.now().difference(last) < _smbIdleDisconnect) {
        _sharedClientLastUsed = DateTime.now();
        // ⭐ 复查修复（2026-10-24）：复用健康连接时**清掉"稍后断开"标记** ✗→✓ ——
        // 否则读完后会把**刚复用好的连接**又断掉 ⇒ 下一张图白重连一次 ✓。
        _closeSharedRequested = false;
        return existing;
      }
    }
    // 闸门已持有（串行 ✓）⇒ 此刻没有别的原生操作 ✓，可以安全断开 ✓。
    await closeSharedSmbClient(force: true);
    final client = SmbClient(config: config);
    try {
      // ⭐ 不加 Dart 层 timeout ✓（见 `readFile` 处的说明 ✓）：原生超时由 `timeoutSeconds: 30` 负责 ✓。
      // ⭐ 2026-10-24：连接也走全局闸门 ✓（`SmbClient` 内部串行 ✓）⇒ 与封面/下载/切章列目录**互斥** ✓。
      await client.connect(high: high);
    } catch (e) {
      try {
        await client.disconnect().timeout(const Duration(seconds: 5));
      } catch (_) {}
      rethrow;
    }
    _sharedClient = client;
    _sharedClientKey = key;
    _sharedClientLastUsed = DateTime.now();
    return client;
  }

  /// ⭐ 2026-10-25：**重置 SMB 运行时** ✓ —— 供设置页「重置 SMB 连接」按钮用 ✓。
  /// 断开复用的连接 ✓ + 强制释放全局闸门 ✓（SMB 操作卡住时的恢复手段 ✓，不必重启 App ✓）。
  static Future<void> resetSmbRuntime() async {
    SmbSerial.forceReset();
    _activeReads = 0;
    _closeSharedRequested = false;
    await closeSharedSmbClient(force: true);
    // ⭐ 2026-10-25：把封面/历史/导入用的**共享客户端**也一起断开 ✓ ——
    // 否则"重置"后它们仍持有旧连接（可能已失效 ✓），用户会以为重置没生效 ✗。
    await SmbClient.closeAllShared();
  }

  /// ⭐ 断开复用的 SMB 连接 ✓（阅读器退出 / 切换章节 / 前台读失败重连时调用 ✓）。
  static Future<void> closeSharedSmbClient({bool force = false}) async {
    if (!force && (_activeReads > 0 || _smbGate.locked)) {
      // ⚠️ **绝不在原生操作进行中断开** ✗ —— libsmb2 会访问冲突崩溃 ✓（已实证 ✓）
      // ⇒ 标记"稍后断开" ✓，等最后一个在途读结束后由 [_maybeCloseSharedClient] 执行 ✓。
      _closeSharedRequested = true;
      return;
    }
    final client = _sharedClient;
    _sharedClient = null;
    _sharedClientKey = null;
    _sharedClientLastUsed = null;
    if (client != null) {
      try {
        // ⭐ 同样不加 Dart 层 timeout ✓（它不会取消原生 disconnect ✓，反而可能在 kill isolate 时崩 ✗）。
        await client.disconnect();
      } catch (_) {
        // 断开失败不影响后续重连 ✓。
      }
    }
  }

  /// ⭐ 在途读结束、且无人持有闸门时，执行"稍后断开" ✓。
  ///
  /// ⭐ 复查修复（2026-10-24）：**断开必须在闸门内 await 完成** ✓ ——
  /// 原先 fire-and-forget 且在 `release()` 之后 ✗ ⇒ 下一个持有者可能同时在 connect ✗（原生层并发 ✗）。
  static Future<void> _maybeCloseSharedClient() async {
    if (!_closeSharedRequested) return;
    if (_activeReads > 0) return;
    if (!await _smbGate.acquire(
      high: false,
      timeout: _smbPrefetchWaitTimeout,
    )) {
      return;
    }
    try {
      if (_activeReads > 0) return;
      _closeSharedRequested = false;
      await closeSharedSmbClient(force: true);
    } finally {
      _smbGate.release();
    }
  }

  /// 读取一页 SMB 图片的字节（**只取字节，不解码**）。
  ///
  /// 顺序：磁盘缓存命中 ⇒ 直接返回；有在途读取 ⇒ 复用；否则占名额 → 读 → 落盘。
  /// [foreground] = true（前台，用户正在等 ✓）用前台名额池；false（预取 ✓）用预取名額池。
  static Future<Uint8List> _readSmbPage(
    String imageKey,
    String cacheKey,
    void Function()? checkStop, {
    bool foreground = true,
  }) async {
    final cached = await CacheManager().findCache(cacheKey);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      if (bytes.isNotEmpty) {
        return Uint8List.fromList(bytes);
      }
    }

    checkStop?.call();

    final existing = _inflightReads[cacheKey];
    if (existing != null) {
      if (!foreground) {
        return existing;
      }
      try {
        return await existing;
      } catch (_) {
        // ⭐ 复查修复（2026-10-24）：前台**不能**吃预取路径的"让路/被跳过"错误 ✗
        //（原先会直接拿到 "SMB prefetch skipped (busy)" ⇒ 当前页报错 ✗）。
        // 吞掉后继续走下面的**前台读** ✓；若该页已取消 ⇒ `checkStop` 会抛"停止" ✓。
        checkStop?.call();
      }
    }

    if (foreground) {
      _lastForegroundReadAt = DateTime.now().millisecondsSinceEpoch;
    }

    final future = _readSmbPageUncached(
      imageKey,
      cacheKey,
      checkStop,
      foreground,
    );
    _inflightReads[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflightReads.remove(cacheKey);
    }
  }

  static Future<Uint8List> _readSmbPageUncached(
    String imageKey,
    String cacheKey,
    void Function()? checkStop,
    bool foreground,
  ) async {
    final config = parseSmbConfigFromUrl(imageKey);
    final remotePath = smbPathFromUrl(imageKey);

    // ① 抢**全局 SMB 闸门** ✓（同一时刻只允许一个原生操作 ✓，否则 libsmb2 会崩 ✗）
    if (foreground) {
      final deadline = DateTime.now().add(_smbForegroundWaitTimeout);
      while (true) {
        // ⭐ 看门狗（复查修复 ✓）：锁被异常卡死时**强制复位** ✓ —— 否则用户只能重启 App ✗。
        if (_smbGate.hasBeenLockedFor(_smbGateWatchdog)) {
          Log.error(
            'SMB Gate',
            'locked too long, force resetting to avoid deadlock',
          );
          _smbGate.reset();
        }
        final granted = await _smbGate.acquire(
          high: true,
          timeout: AppMotion.short,
        );
        if (granted) break;
        // 该页若已被取消 ⇒ 这里抛"停止" ✓ ⇒ 上游按取消处理 ✓（不报错、不重载 ✓）。
        checkStop?.call();
        if (DateTime.now().isAfter(deadline)) {
          throw "Error: SMB read busy.";
        }
      }
    } else {
      // 预取：等不到就让路 ✓（前台永远优先 ✓）
      if (!await _smbGate.acquire(
        high: false,
        timeout: _smbPrefetchWaitTimeout,
      )) {
        throw "Error: SMB prefetch skipped (busy).";
      }
    }

    try {
      // 拿到名额后**再判一次停** ✓：等待期间用户可能已经翻走 ✓。
      if (foreground) {
        checkStop?.call();
      }
      late final Uint8List data;
      var readStarted = false;
      try {
        final client = await _obtainClient(config, high: foreground);
        _activeReads++;
        readStarted = true;
        // ⭐ 复查修复（2026-10-24）：**不要给原生读加 Dart 层 timeout** ✗ ——
        // `.timeout()` **不会取消** libsmb2 的原生读 ✓；超时后我们若立刻断开 ✗，
        // 就会在 FFI 仍在运行时强杀 isolate ⇒ **0xc0000005 访问冲突** ✓（事件日志实证 ✓）。
        // 原生层自己的超时来自 `SmbClient.connect(timeoutSeconds: 30)` ✓；
        // 真卡死时靠 [_smbGate] 的**看门狗复位**兜底 ✓（见下面前台等待循环 ✓）。
        // ⭐ 2026-10-24：`high: foreground` ⇒ 前台读图优先，后台读（预取）让路 ✓。
        data = await client.readFile(remotePath, high: foreground);
        if (data.isEmpty) {
          throw "Error: Empty response body.";
        }
      } catch (e) {
        // ⚠️ **绝不在读到一半时断开原生连接** ✗（正是 libsmb2 访问冲突的成因 ✓）
        // ⇒ 只标记"稍后断开" ✓，下次读由 [_obtainClient] 自动重连 ✓。
        _closeSharedRequested = true;
        Log.error('SMB Reader', e);
        rethrow;
      } finally {
        if (readStarted) {
          _activeReads--;
        }
      }
      // ⭐ 先落盘再判停：即便本页已被判停，字节也进了缓存，
      // 下次进入该页直接命中 ⇒ 正是本次修复要的"不再闪烁"。
      await CacheManager().writeCache(cacheKey, data, _smbPageCacheDuration);
      _sharedClientLastUsed = DateTime.now();
      if (foreground) {
        checkStop?.call();
      }
      return data;
    } finally {
      _smbGate.release();
      // ⭐ 复查修复：**await** 断开（在闸门内完成 ✓），避免与下一个 connect 并发 ✗。
      await _maybeCloseSharedClient();
    }
  }

  /// ⭐ 新增（2026-10-24）：SMB 页「落盘预取」—— 后台把该页字节读进磁盘缓存，**不解码**。
  ///
  /// 供 `pages/reader/images.dart` 的 `_preDownloadImage` 调用：这是"预加载图片数量"
  /// 对 SMB 该有的语义（备好字节，不占解码内存）。预取只是优化，失败必须静默
  /// （不能影响阅读 ✓，也**不能挡住前台** ✓）。
  static Future<void> prefetchSmbPage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) async {
    if (!imageKey.startsWith('smb://')) {
      return;
    }
    final cacheKey = "$imageKey@$sourceKey@$cid@$eid";
    final queuedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      // 已有缓存 / 已有在途读取 ⇒ 不必再排队 ✓。
      if (await CacheManager().findCache(cacheKey) != null) {
        return;
      }
      if (_inflightReads.containsKey(cacheKey)) {
        return;
      }
      // ⭐ 排队前先看一次"是否已过时" ✓（快速翻页时本函数会被连续调用很多次 ✓）。
      if (_lastForegroundReadAt > queuedAt) {
        return;
      }
      await _readSmbPage(imageKey, cacheKey, null, foreground: false);
    } catch (_) {
      // 静默：目标页可能不在、或 NAS 暂时不可达、或排队超时被丢弃 ✓ —— 都正常。
    }
  }

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "$imageKey@$sourceKey@$cid@$eid@$enableResize";

  /// ⭐ 修复（2026-10-09）：磁盘写入键**不含** `@enableResize`（见 `network/images.dart` 的 writeCache），
  /// 覆写后解码失败的清理才能命中真实缓存文件。
  @override
  String get cacheKey => "$imageKey@$sourceKey@$cid@$eid";

  @override
  void onLoadError() {
    // ⭐ 复查修复（2026-10-24）：SMB 的**页列表缓存键对不上** ✗ ——
    // 页列表写入用的是 `loadComicPages@${reader.type.sourceKey}@…`（SMB 为 `@smb@` ✓），
    // 而这里构造的是 `loadComicPages@$sourceKey@…`，SMB 的 `sourceKey == null` ⇒ 得到 `@null@` ✓
    // ⇒ 删不到真正的缓存 ✗，还可能误删别的源 ✓。SMB 不做这步 ✓（其它源行为不变 ✓）。
    if (!imageKey.startsWith('smb://')) {
      var cacheKey = "loadComicPages@$sourceKey@$cid@$eid";
      CacheManager().delete(cacheKey);
    }
    onLoadFailed?.call();
  }
}
