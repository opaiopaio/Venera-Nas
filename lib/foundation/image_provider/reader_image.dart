import 'dart:async' show Completer, Future, Timer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'reader_image.dart' as image_provider;

/// 简易信号量，用于限制并发异步操作。
///
/// 说明（2026-10-24）：`local_comic_image.dart` 里已有同名实现，但它是**文件私有**的（`_` 前缀
/// 只在所属库内可见），跨文件无法复用 ⇒ 这里单独写一份等价实现。
class _Semaphore {
  _Semaphore(this._maxCount);

  final int _maxCount;

  int _current = 0;

  final List<Completer<bool>> _waiters = [];

  Future<void> acquire() async {
    await tryAcquire(null);
  }

  /// ⭐ 2026-10-24（修订 ✓）：支持**有超时的排队** —— 预取任务等不到名额就**放弃** ✓，
  /// 而不是像 `acquire()` 一样无限等下去（等待中的任务同样占着内存与调用栈 ✓）。
  /// 返回 `true` = 拿到名额（调用方必须 `release()` ✓）；`false` = 超时放弃 ✓。
  Future<bool> tryAcquire(Duration? timeout) async {
    if (_current < _maxCount) {
      _current++;
      return true;
    }
    final c = Completer<bool>();
    _waiters.add(c);
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!c.isCompleted) {
          _waiters.remove(c);
          c.complete(false);
        }
      });
    }
    final granted = await c.future;
    timer?.cancel();
    return granted;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // 名额**直接移交**给下一个等待者 ✓（`_current` 不变 ✓）。
      _waiters.removeAt(0).complete(true);
    } else {
      _current--;
    }
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
  });

  final String imageKey;

  final String? sourceKey;

  final String cid;

  final String eid;

  final int page;

  final void Function()? onLoadFailed;

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
      imageBytes = await _readSmbPage(imageKey, cacheKey, checkStop);
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

  /// ⭐ 2026-10-24（修订 ✗→✓）：**前台读图与后台预取必须分离限流** ✗
  ///
  /// 首版把两者共用同一个 `_Semaphore(2)` ✓ ⇒ 快速翻页时**预取任务排在等待队列前面** ✗
  /// （FIFO ✓），当前页迟迟抢不到名额 ⇒ 表现为**一直转圈、随后卡死闪退** ✗（Windows 实测 ✓）。
  /// 现在拆成两个**互不抢占**的名额池 ✓：
  /// - 前台（用户正在等的当前页 / 相邻页 ✓）：2 个名额 ✓，不排队就绪时几乎立即开始 ✓
  /// - 后台预取（只落盘、不解码 ✓）：1 个名额 ✓，且**等不到就放弃** ✓ ⇒ 永不挡住前台 ✓
  static final _smbForegroundSemaphore = _Semaphore(2);

  static final _smbPrefetchSemaphore = _Semaphore(1);

  /// 前台读图最近一次开始的毫秒时间戳 ✓ —— 预取据此判断"用户正在翻页 ⇒ 本页已过时 ⇒ 丢弃" ✓。
  static int _lastForegroundReadAt = 0;

  /// 前台读图**序号** ✓ —— 用于快速翻页时丢弃"排队排太久、已经被新页超过"的旧请求 ✓。
  ///
  /// 为什么需要（2026-10-24 Windows 实测 ✓）：快速连续翻页会同时产生多个前台读图请求 ✓，
  /// 名额只有 2 个 ⇒ 旧页在队列里排队 ✓；而用户此刻要看的是**新页** ✗。
  /// 若不丢弃旧请求，旧页会一个个依次读完 ⇒ 新页长时间转圈（用户感受 = "加载不出来" ✗）。
  static int _foregroundSeq = 0;

  /// SMB 单次读取（connect / readFile / disconnect）的超时 ✓ ——
  /// 避免 NAS 无响应时**永远转圈** ✗（超时抛错 ⇒ 走既有的 NetworkError + 重试界面 ✓）。
  static const _smbIoTimeout = Duration(seconds: 20);

  /// 预取排队超时 ✓：名额被占就放弃 ✓（预取是可丢的 ✓，前台不可堵 ✗）。
  static const _smbPrefetchWaitTimeout = Duration(seconds: 3);

  /// 同一页**在途读取去重** ✓：`load` 与预取可能同时触发同一页 ✗ ⇒ 共用一个 Future ✓。
  static final Map<String, Future<Uint8List>> _inflightReads = {};

  /// SMB 页磁盘缓存有效期：7 天（漫画页不会变，长有效期才能让"回头翻"命中）。
  static const _smbPageCacheDuration = 7 * 24 * 60 * 60 * 1000;

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
      return existing;
    }

    if (foreground) {
      _lastForegroundReadAt = DateTime.now().millisecondsSinceEpoch;
    }

    final seq = foreground ? ++_foregroundSeq : 0;

    final future = _readSmbPageUncached(
      imageKey,
      cacheKey,
      checkStop,
      foreground,
      seq,
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
    int seq,
  ) async {
    final config = parseSmbConfigFromUrl(imageKey);
    final remotePath = smbPathFromUrl(imageKey);

    final semaphore = foreground
        ? _smbForegroundSemaphore
        : _smbPrefetchSemaphore;
    // 预取若在 3 秒内等不到名额 ⇒ 直接放弃 ✓（不排队、不累积 ✓）。
    final granted = await semaphore.tryAcquire(
      foreground ? null : _smbPrefetchWaitTimeout,
    );
    if (!granted) {
      throw "Error: SMB read skipped (busy).";
    }
    try {
      // 拿到名额后**再判一次停** ✓：等待期间用户可能已经翻走 ✓。
      if (foreground) {
        checkStop?.call();
        // ⭐ 快速翻页：排队期间已经有 ≥3 个更新的前台请求 ⇒ 本页已不是用户要看的那页 ⇒ 丢弃 ✓。
        // 只丢弃"排队等过"的（`_foregroundSeq` 从进入排队到现在增加了 2 个以上 ✓），
        // 立即拿到名额的请求不受影响 ✓ ⇒ 正常翻页体验不变 ✓。
        if (_foregroundSeq - seq > 2) {
          throw "Error: SMB read skipped (stale).";
        }
      }
      final client = SmbClient(config: config);
      late final Uint8List data;
      try {
        await client.connect().timeout(_smbIoTimeout);
        data = await client.readFile(remotePath).timeout(_smbIoTimeout);
        if (data.isEmpty) {
          throw "Error: Empty response body.";
        }
      } catch (e) {
        // 判停走的是另一条路径（不进这里）✓；这里只记真正的读取失败 ✓。
        Log.error('SMB Reader', e);
        rethrow;
      } finally {
        try {
          await client.disconnect().timeout(const Duration(seconds: 5));
        } catch (_) {
          // 断开失败不影响本次结果 ✓（连接会随对象释放回收 ✓）。
        }
      }
      // ⭐ 先落盘再判停：即便本页已被判停，字节也进了缓存，
      // 下次进入该页直接命中 ⇒ 正是本次修复要的"不再闪烁"。
      await CacheManager().writeCache(cacheKey, data, _smbPageCacheDuration);
      if (foreground) {
        checkStop?.call();
      }
      return data;
    } finally {
      semaphore.release();
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
    var cacheKey = "loadComicPages@$sourceKey@$cid@$eid";
    CacheManager().delete(cacheKey);
    onLoadFailed?.call();
  }
}
