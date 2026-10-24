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
import 'local_comic_image.dart' show SmbCoverLoader;
import 'reader_image.dart' as image_provider;

/// ⭐ 2026-10-24：**SMB 原生操作的全局串行闸门** ✓
///
/// 崩溃实证（Windows 事件日志 ✓）：`libsmb2.dll` 报 **0xc0000005 访问冲突** ✗ ——
/// 原生库不能被"同一连接并发使用"或"读到一半被 disconnect" ✗。
/// 所以所有 SMB 操作必须**一次只做一件** ✓；本闸门让**前台请求优先** ✓、预取等不到就丢 ✓。
class _SmbGate {
  _SmbGate({this.max = 1});

  /// ⭐ 2026-10-25：**并发名额**（1 = 串行 ✓；>1 = 流式并发 ✓）。
  /// 用户反馈"最后一页要等前面全加载完"✗ ⇒ 阅读器读图改为**并发 2** ✓：
  /// 当前页与相邻页可以**同时读** ✓（真正"云端流式"体验 ✓），
  /// 同时不至于把 NAS/路由器打满 ✓（配合 [ImageCache] 与预取节流 ✓）。
  final int max;

  int _current = 0;

  /// 当前持锁方的开始时间 ✓ —— 用于**看门狗**：异常情况下锁被卡死时强制复位 ✓（否则用户只能重启 App ✗）。
  DateTime? _lockedAt;

  final List<Completer<bool>> _high = [];

  final List<Completer<bool>> _low = [];

  bool get locked => _current > 0;

  /// 持锁超过 [limit] ⇒ 判定卡死 ✓（由调用方决定是否 [reset] ✓）。
  bool hasBeenLockedFor(Duration limit) {
    final at = _lockedAt;
    return _current > 0 && at != null && DateTime.now().difference(at) > limit;
  }

  /// ⚠️ 强制复位 ✓：把锁与所有等待者都放掉 ✓（等待者按"失败"返回 ⇒ 走可重试错误 ✓）。
  ///
  /// 只在看门狗判定卡死时调用 ✓ —— 这是"不重启 App 也能恢复"的唯一兜底 ✓。
  void reset() {
    _current = 0;
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
    if (_current < max) {
      _current++;
      _lockedAt ??= DateTime.now();
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
    if (_current > 0) {
      _current--;
    }
    if (_current == 0) {
      _lockedAt = null;
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
  /// ⭐ 2026-10-25：**并发 2** ✓ —— 当前页 + 相邻页可同时读 ✓（流式体验 ✓）；
  /// 预取仍需排队 ✓（不会把 NAS 打满 ✗）。
  static final _smbGate = _SmbGate(max: 2);

  /// 在途的 SMB **原生读**计数 ✓ —— 只有为 0 才允许 disconnect ✓（防 use-after-free ✓）。
  ///
  /// ⭐ 2026-10-25：**重置时不再清零** ✓ —— 清零会让"重置"误以为没有读在跑 ✗，
  /// 随后 force disconnect 会撞上仍在执行的同步 FFI ✗（`0xc0000005` ✓）。
  static int _activeReads = 0;

  /// 等待安全时机再断开的旧连接 ✓（可能是换配置 / 读失败 / 重置产生的 ✓）。
  ///
  /// ⭐ 2026-10-25：不再用单个 bool 标记 ✗ —— 重连时标记会落到**新连接**上，
  /// 等旧读结束反而把刚建好的连接断掉 ✗。这里按对象排队 ✓，只断指定的旧池 ✓。
  static final List<SmbClient> _clientsPendingClose = [];

  /// ⭐ 2026-10-25：**_obtainClient 单飞** ✓（见 [_obtainClient] ✓）。
  static Future<SmbClient>? _clientOpening;

  static String? _clientOpeningKey;

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

  /// SMB 页磁盘缓存有效期 ✓ —— ⭐ 2026-10-25 用户确认：**3~7 天可接受** ✓ ⇒ 取 **7 天** ✓。
  /// （缓存上限与 LRU 现在都能正常工作 ✓，不会再像之前那样无限涨到 5 GB ✗）
  static const _smbPageCacheDuration = 7 * 24 * 60 * 60 * 1000;

  /// ⭐ 复用的 SMB 连接 ✓（整段阅读共用一条 ✓；退出阅读器时由 [closeSharedSmbClient] 断开 ✓）。
  static SmbClient? _sharedClient;

  static String? _sharedClientKey;

  static DateTime? _sharedClientLastUsed;

  /// 取得（必要时建立）复用的 SMB 连接 ✓。
  ///
  /// [high] = true 表示"用户在等"（当前页 ✓）—— 会优先于后台任务拿到全局 SMB 闸门 ✓。
  ///
  /// ⭐ 2026-10-25（P1 ✓）：**单飞 Future 初始化** ✓ —— 阅读器并发 2 时，
  /// 原实现是 check-then-act ✗：两条路径同时看到"没有可用连接" ⇒ 各建一个池 ✓，
  /// 后完成的覆盖前一个 ⇒ 泄漏 4 个 isolate ✓。现在所有同配置调用共享同一个
  /// Future ✓；不同配置则排队等前一个结束后再重试 ✓（不并发建池 ✓）。
  static Future<SmbClient> _obtainClient(
    SmbConfig config, {
    bool high = false,
  }) {
    // ⭐ 2026-10-25：连接复用键统一走 `SmbClient.cacheKey` ✓ ——
    // 原先这里与 `SmbClient._keyOf` 各拼一份 ✗ ⇒ 两边一旦有一边加了字段（如协议选项 ✓），
    // 同一个共享就会被判成两个会话 ✗（池被重复建 ✓）。
    final key = SmbClient.cacheKey(config);

    final opening = _clientOpening;
    if (opening != null) {
      if (_clientOpeningKey == key) {
        return opening;
      }
      // 不同配置（例如切漫画）不能并行建池 ✓：等前一个收尾后重试 ✓。
      return opening.then(
        (_) => _obtainClient(config, high: high),
        onError: (_) => _obtainClient(config, high: high),
      );
    }

    final existing = _sharedClient;
    if (existing != null && _sharedClientKey == key && existing.isConnected) {
      final last = _sharedClientLastUsed;
      if (last == null ||
          DateTime.now().difference(last) < _smbIdleDisconnect) {
        _sharedClientLastUsed = DateTime.now();
        return Future.value(existing);
      }
    }

    final future = _openSharedClient(config, key, high: high);
    _clientOpening = future;
    _clientOpeningKey = key;
    future.whenComplete(() {
      if (identical(_clientOpening, future)) {
        _clientOpening = null;
        _clientOpeningKey = null;
      }
    }).ignore();
    return future;
  }

  /// 真正建立连接的路径 ✓（只会由 [_obtainClient] 的单飞 Future 调用 ✓）。
  static Future<SmbClient> _openSharedClient(
    SmbConfig config,
    String key, {
    required bool high,
  }) async {
    // ⚠️ 不在这里 `closeSharedSmbClient(force: true)` ✗ ——
    // 另一个并发读可能正用着旧池 ✓，force 会把它从 FFI 底下抽走 ✗。
    // 旧池只摘引用并**排队等安全时机**再断 ✓。
    final stale = _sharedClient;
    if (stale != null) {
      _detachSharedClient(stale);
      _scheduleClientClose(stale);
    }

    final client = SmbClient(config: config);
    try {
      // ⭐ 不加 Dart 层 timeout ✓（见 `readFile` 处的说明 ✓）：原生 connect 超时 30s，
      // Dart 层给到 40s 兜底 ✓。
      // ⭐ 2026-10-24：连接也走全局闸门 ✓（`SmbClient` 内部串行 ✓）⇒ 与封面/下载/切章列目录**互斥** ✓。
      await client.connect(high: high);
    } catch (e) {
      // 新建的池不会与阅读器共享 ✓，失败时直接安全断开（内部也会先 drain ✓）。
      try {
        await client.disconnect();
      } catch (_) {}
      rethrow;
    }
    _sharedClient = client;
    _sharedClientKey = key;
    _sharedClientLastUsed = DateTime.now();
    return client;
  }

  /// 摘掉共享引用 ✓（只清仍指向 [client] 的字段 ✓，避免误清新连接 ✗）。
  static void _detachSharedClient(SmbClient client) {
    if (!identical(_sharedClient, client)) return;
    _sharedClient = null;
    _sharedClientKey = null;
    _sharedClientLastUsed = null;
  }

  /// 排队等待安全时机断开 [client] ✓（相同对象只排一次 ✓）。
  static void _scheduleClientClose(SmbClient client) {
    if (_clientsPendingClose.any((c) => identical(c, client))) return;
    _clientsPendingClose.add(client);
  }

  /// ⭐ 2026-10-25：**重置 SMB 运行时** ✓ —— 供设置页「重置 SMB 连接」按钮用 ✓。
  ///
  /// ⭐ P0 相关：**不清 [_activeReads]、不 force 断在途读** ✗ ——
  /// 强制断开正在同步 FFI 的连接就是 `0xc0000005` 的成因 ✓。
  /// 这里只把闸门放掉（让卡死的等待者失败 ✓），连接交给 [_maybeCloseSharedClients]
  /// 在最后一个读结束后再断 ✓。用户看到的"已重置"= 等待队列已清空 ✓。
  static Future<void> resetSmbRuntime() async {
    SmbSerial.forceReset();
    // ⭐ 必须一起复位阅读器自己的闸门 ✓：否则 SmbSerial 放掉了、_smbGate 还锁着，
    // 新的读仍然会排队到超时 ✗。
    _smbGate.reset();
    // 安全时立即断，否则排队 ✓（不修改 _activeReads ✓）。
    await closeSharedSmbClient(force: _activeReads == 0);
    // ⭐ 2026-10-25：把封面/历史/导入用的**共享客户端**也一起断开 ✓ ——
    // 否则"重置"后它们仍持有旧连接（可能已失效 ✓），用户会以为重置没生效 ✗。
    // （[SmbClient.closeAllShared] 会清空池 + 取消空闲巡检定时器 ✓）
    await SmbClient.closeAllShared();
    // ⭐ 2026-10-25：重置意味着"服务器配置/网络环境可能已经变了" ✓ ⇒ 一并清掉
    // ①URL ⇒ SmbConfig 解析缓存 ✓（否则还按旧凭据/端口建连 ✗）；
    // ②封面"已知缺失"记录 ✓（否则服务器修好后封面仍会一直 404 ✗）。
    invalidateSmbConfigCache();
    SmbCoverLoader.clearFailures();
  }

  /// ⭐ 断开复用的 SMB 连接 ✓（阅读器退出 / 切换章节 / 前台读失败重连时调用 ✓）。
  static Future<void> closeSharedSmbClient({bool force = false}) async {
    final client = _sharedClient;
    if (client == null) return;
    // 先摘引用 ✓：即使稍后才真正断，新读也不会再拿到这条待断连接 ✓。
    _detachSharedClient(client);

    if (_activeReads > 0 || (!force && _smbGate.locked)) {
      // ⚠️ **绝不在原生操作进行中断开** ✗ —— libsmb2 会访问冲突崩溃 ✓（已实证 ✓）
      // ⇒ 排队 ✓，等最后一个在途读结束后由 [_maybeCloseSharedClients] 执行 ✓。
      _scheduleClientClose(client);
      return;
    }
    try {
      await client.disconnect();
    } catch (_) {
      // 断开失败不影响后续重连 ✓。
    }
  }

  /// ⭐ 在途读结束、且无人持有闸门时，执行排队中的断开 ✓。
  ///
  /// ⭐ 复查修复（2026-10-24）：**断开必须在闸门内 await 完成** ✓ ——
  /// 原先 fire-and-forget 且在 `release()` 之后 ✗ ⇒ 下一个持有者可能同时在 connect ✗（原生层并发 ✗）。
  static Future<void> _maybeCloseSharedClients() async {
    if (_clientsPendingClose.isEmpty) return;
    if (_activeReads > 0) return;
    if (!await _smbGate.acquire(
      high: false,
      timeout: _smbPrefetchWaitTimeout,
    )) {
      return;
    }
    try {
      if (_activeReads > 0) return;
      while (_clientsPendingClose.isNotEmpty) {
        final client = _clientsPendingClose.removeAt(0);
        try {
          await client.disconnect();
        } catch (_) {
          // 单条失败不影响其它排队连接 ✓。
        }
      }
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
    int? prefetchQueuedAt,
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
      prefetchQueuedAt: prefetchQueuedAt,
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
    bool foreground, {
    int? prefetchQueuedAt,
  }) async {
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
        throw "Invalid Status Code: 404 (SMB prefetch skipped, busy)";
      }
    }

    try {
      // 拿到名额后**再判一次停** ✓：等待期间用户可能已经翻走 ✓。
      if (foreground) {
        checkStop?.call();
      }
      late final Uint8List data;
      var readStarted = false;
      SmbClient? readClient;
      try {
        final client = await _obtainClient(config, high: foreground);
        readClient = client;
        _activeReads++;
        readStarted = true;
        // ⭐ 复查修复（2026-10-24）：**不要给原生读加 Dart 层 timeout** ✗ ——
        // `.timeout()` **不会取消** libsmb2 的原生读 ✓；超时后我们若立刻断开 ✗，
        // 就会在 FFI 仍在运行时强杀 isolate ⇒ **0xc0000005 访问冲突** ✓（事件日志实证 ✓）。
        // 原生 connect 超时 30s（Dart 层 40s 兜底），且原生读本身没有 Dart 层超时 ✓；
        // 真卡死时靠 [_smbGate] 的**看门狗复位**兜底 ✓（见下面前台等待循环 ✓）。
        // ⭐ 2026-10-24：`high: foreground` ⇒ 前台读图优先，后台读（预取）让路 ✓。
        data = await client.readFile(remotePath, high: foreground);
        if (data.isEmpty) {
          throw "Error: Empty response body.";
        }
      } catch (e) {
        // ⚠️ **绝不在读到一半时断开原生连接** ✗（正是 libsmb2 访问冲突的成因 ✓）
        // ⇒ 只把这条连接**排队**等安全时机断 ✓，下次读由 [_obtainClient] 自动重连 ✓。
        if (readClient != null && identical(_sharedClient, readClient)) {
          _detachSharedClient(readClient);
          _scheduleClientClose(readClient);
        }
        Log.error('SMB Reader', e);
        rethrow;
      } finally {
        if (readStarted) {
          _activeReads--;
        }
      }
      // ⭐ 2026-10-25：**预取也写盘** ✓ —— 但仅在"用户没有在排队后又翻页"的窗口内 ✓。
      // 原实现 foreground:false 一律不写 ✗ ⇒ 预取读到的字节读完就丢，下一次翻到还要重读 ✗。
      // 现在用 [prefetchQueuedAt] 判断：排队后若又发生了前台读（[_lastForegroundReadAt] 前进 ✓），
      // 说明预取已经过时 ⇒ 不写盘 ✓（既保留流式体验，又不让整本漫画堆满磁盘 ✓）。
      final prefetchStillInWindow =
          foreground ||
          (prefetchQueuedAt != null &&
              _lastForegroundReadAt <= prefetchQueuedAt);
      if (prefetchStillInWindow) {
        await CacheManager().writeCache(cacheKey, data, _smbPageCacheDuration);
      }
      _sharedClientLastUsed = DateTime.now();
      if (foreground) {
        checkStop?.call();
      }
      return data;
    } finally {
      _smbGate.release();
      // ⭐ 复查修复：**await** 断开（在闸门内完成 ✓），避免与下一个 connect 并发 ✗。
      await _maybeCloseSharedClients();
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
    // ⭐ 2026-10-25：统一走 [pageCacheKey] ✓ —— 与前台读 / `cacheKey` 逐字一致 ✓
    //（预取写盘、前台读盘、窗口淘汰必须命中同一个键 ✓）。
    final cacheKey = pageCacheKey(imageKey, sourceKey, cid, eid);
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
      await _readSmbPage(
        imageKey,
        cacheKey,
        null,
        foreground: false,
        // ⭐ 带上排队时间 ✓：读完后若用户已经翻走，这一页就不写盘 ✓（限窗口 ✓）。
        prefetchQueuedAt: queuedAt,
      );
    } catch (_) {
      // 静默：目标页可能不在、或 NAS 暂时不可达、或排队超时被丢弃 ✓ —— 都正常。
    }
  }

  /// ⭐ 2026-10-25：**单页图片磁盘缓存键的唯一出口** ✓ —— `$imageKey@$sourceKey@$cid@$eid` ✓。
  ///
  /// 为什么提取 ✓：同一串键原先在 `ReaderImageProvider.cacheKey`、SMB 预取
  /// （[prefetchSmbPage]）与 `pages/reader/images.dart` 里**各写一遍** ✗
  /// ⇒ 任一处漏改就会"写进去的和查出来的不是同一个文件" ✗（历史上已经踩过
  /// `@smb@` / `@null@` 不一致的坑 ✓）。
  ///
  /// ⚠️ 格式必须与 `network/images.dart` 的 `loadComicImage` **逐字一致** ✗ ——
  /// 那边的磁盘读写键仍是行内拼接（不属本次可改范围 ✓），改动这里等于改缓存协议 ✓。
  /// `sourceKey` 为 null 时会插值成字符串 `null` ✓（与既有缓存文件兼容 ✓）。
  static String pageCacheKey(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) => "$imageKey@$sourceKey@$cid@$eid";

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "$imageKey@$sourceKey@$cid@$eid@$enableResize";

  /// ⭐ 修复（2026-10-09）：磁盘写入键**不含** `@enableResize`（见 `network/images.dart` 的 writeCache），
  /// 覆写后解码失败的清理才能命中真实缓存文件。
  @override
  String get cacheKey => pageCacheKey(imageKey, sourceKey, cid, eid);

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
