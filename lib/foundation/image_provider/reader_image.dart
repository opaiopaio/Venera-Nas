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

  /// ⭐ 2026-10-24（第三次修订 ✗→✓）：**当前页最高优先 + 只保留最新请求 + SMB 连接复用**
  ///
  /// 前两版的教训（均为用户实测 ✓）：
  /// 1. 前台与预取**共用**名额池 ⇒ 预取把前台堵住 ⇒ **一直转圈** ✗
  /// 2. 前台 2 个名额 + FIFO 排队 ⇒ 滚轮连续切页时**旧页的读取还占着名额** ✗，
  ///    当前页要等旧页读完 ⇒ **仍然转圈** ✗（用户原话："应该优先加载当前页" ✓）
  ///
  /// 现在 ✓：
  /// - 前台**只 1 个名额** ✓ 且等待队列**只保留最新请求** ✓（新页到达 ⇒ 旧等待者立即作废 ✓）
  ///   ⇒ 当前页永远排最前 ✓
  /// - 预取**只在"前台完全空闲"时**才启动 ✓（名额 1 ✓、等不到就丢 ✓）⇒ 不抢前台 ✓
  /// - ⭐ **SMB 连接复用** ✓：整段阅读共用一条连接 ✓（原先每页新建 = 4 isolate + TCP + 认证 ✗，
  ///   单页几百毫秒 ⇒ 快速翻页必然转圈 ✓）
  static final _smbPrefetchSemaphore = _Semaphore(1);

  /// 前台读图最近一次开始的毫秒时间戳 ✓ —— 预取据此判断"用户正在翻页 ⇒ 丢弃预取" ✓。
  static int _lastForegroundReadAt = 0;

  /// 前台是否正在读（单名额 ✓：SMB 读是 IO 密集 ✓，串行反而更快更省 ✓）。
  static bool _foregroundBusy = false;

  /// 前台等待者（**最多 1 个 ✓**；新请求到达时旧的立即作废 ✓）。
  static Completer<bool>? _foregroundWaiter;

  /// 前台等待超时 ✓：超时视为被顶掉 ⇒ 抛可重试错误 ✓（不会无限转圈 ✗）。
  static const _smbForegroundWaitTimeout = Duration(seconds: 15);

  /// SMB IO 超时 ✓（connect / readFile / disconnect ✓）。
  static const _smbIoTimeout = Duration(seconds: 20);

  /// 预取排队超时 ✓。
  static const _smbPrefetchWaitTimeout = Duration(seconds: 3);

  /// 复用连接的**空闲断开**时长 ✓（避免在 NAS 上挂长期空闲会话 ✓）。
  static const _smbIdleDisconnect = Duration(seconds: 60);

  /// 同一页**在途读取去重** ✓：`load` 与预取可能同时触发同一页 ✗ ⇒ 共用一个 Future ✓。
  static final Map<String, Future<Uint8List>> _inflightReads = {};

  /// SMB 页磁盘缓存有效期：7 天（漫画页不会变，长有效期才能让"回头翻"命中）。
  static const _smbPageCacheDuration = 7 * 24 * 60 * 60 * 1000;

  /// ⭐ 复用的 SMB 连接 ✓（整段阅读共用一条 ✓；退出阅读器时由 [closeSharedSmbClient] 断开 ✓）。
  static SmbClient? _sharedClient;

  static String? _sharedClientKey;

  static DateTime? _sharedClientLastUsed;

  /// 取得（必要时建立）复用的 SMB 连接 ✓。
  static Future<SmbClient> _obtainClient(SmbConfig config) async {
    final key =
        '${config.host}|${config.port}|${config.share}|'
        '${config.username}|${config.password.hashCode}|${config.domain}';
    final existing = _sharedClient;
    if (existing != null && _sharedClientKey == key && existing.isConnected) {
      final last = _sharedClientLastUsed;
      if (last == null ||
          DateTime.now().difference(last) < _smbIdleDisconnect) {
        _sharedClientLastUsed = DateTime.now();
        return existing;
      }
    }
    await closeSharedSmbClient();
    final client = SmbClient(config: config);
    try {
      await client.connect().timeout(_smbIoTimeout);
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

  /// ⭐ 断开复用的 SMB 连接 ✓（阅读器退出 / 切换章节 / 前台读失败重连时调用 ✓）。
  static Future<void> closeSharedSmbClient() async {
    final client = _sharedClient;
    _sharedClient = null;
    _sharedClientKey = null;
    _sharedClientLastUsed = null;
    if (client != null) {
      try {
        await client.disconnect().timeout(const Duration(seconds: 5));
      } catch (_) {
        // 断开失败不影响后续重连 ✓。
      }
    }
  }

  static bool get _foregroundIdle =>
      !_foregroundBusy && _foregroundWaiter == null;

  /// 前台抢名额 ✓：只有 1 个 ✓，**最新请求顶掉旧等待者** ✓，且**被顶掉时安静重试** ✓。
  ///
  /// ⚠️ 为什么不能"抛错丢弃"（2026-10-24 用户实测 ✓）：抛错会让 provider 走失败重试 →
  /// `onLoadError` →（原先）"页面列表失效" → **整页弹大圈重载** ✗。
  /// 现在：一直被顶掉就重试 ✓；该页真的被取消（用户翻走 ✓）时 `checkStop` 会抛"停止" ✓ ⇒ 干净退出 ✓。
  static Future<void> _acquireForeground(void Function()? checkStop) async {
    if (!_foregroundBusy) {
      _foregroundBusy = true;
      return;
    }
    final deadline = DateTime.now().add(_smbForegroundWaitTimeout);
    while (true) {
      final old = _foregroundWaiter;
      if (old != null && !old.isCompleted) {
        // 旧等待者作废 ✓：它对应的页已经不是用户要看的那页 ✓。
        old.complete(false);
      }
      final c = Completer<bool>();
      _foregroundWaiter = c;
      var granted = false;
      try {
        granted = await c.future.timeout(
          AppMotion.short,
          onTimeout: () => false,
        );
      } finally {
        if (identical(_foregroundWaiter, c)) {
          _foregroundWaiter = null;
        }
      }
      if (granted) {
        return;
      }
      // 该页若已被取消 ⇒ 这里会抛"停止"异常 ⇒ 上游按取消处理 ✓（不写失败日志、不重载 ✓）。
      checkStop?.call();
      if (DateTime.now().isAfter(deadline)) {
        throw "Error: SMB read busy.";
      }
    }
  }

  static void _releaseForeground() {
    final waiter = _foregroundWaiter;
    if (waiter != null && !waiter.isCompleted) {
      // 名额直接移交给最新等待者 ✓（`_foregroundBusy` 保持 true ✓）。
      _foregroundWaiter = null;
      waiter.complete(true);
    } else {
      _foregroundBusy = false;
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
      return existing;
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

    if (foreground) {
      await _acquireForeground(checkStop);
    } else {
      // ⭐ 预取只在"前台完全空闲"时进行 ✓ —— 用户还在翻页就**立刻放弃** ✓，绝不抢前台 ✓。
      if (!_foregroundIdle) {
        throw "Error: SMB prefetch skipped (busy).";
      }
      final granted = await _smbPrefetchSemaphore.tryAcquire(
        _smbPrefetchWaitTimeout,
      );
      if (!granted) {
        throw "Error: SMB prefetch skipped (busy).";
      }
      if (!_foregroundIdle) {
        _smbPrefetchSemaphore.release();
        throw "Error: SMB prefetch skipped (busy).";
      }
    }

    try {
      // 拿到名额后**再判一次停** ✓：等待期间用户可能已经翻走 ✓。
      if (foreground) {
        checkStop?.call();
      }
      late final Uint8List data;
      try {
        final client = await _obtainClient(config);
        data = await client.readFile(remotePath).timeout(_smbIoTimeout);
        if (data.isEmpty) {
          throw "Error: Empty response body.";
        }
      } catch (e) {
        // ⭐ 前台读失败 ⇒ 丢掉复用连接（可能已失效 ✓），下次自动重连 ✓；
        // 预取失败不动共享连接 ✓（否则会把正在使用的前台连接一起关掉 ✗）。
        if (foreground) {
          await closeSharedSmbClient();
        }
        Log.error('SMB Reader', e);
        rethrow;
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
      if (foreground) {
        _releaseForeground();
      } else {
        _smbPrefetchSemaphore.release();
      }
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
