import 'dart:async' show Completer, Future;
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

  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_current < _maxCount) {
      _current++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
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

  /// ⭐ 新增（2026-10-24）：SMB 读图的**全局并发上限**。
  /// 原因：原先每次读图都新建一个 SMB 连接（内部含 4 个 isolate 的池），预加载一开
  /// 会同时拉起多条连接 ⇒ 内存与句柄双双飙升，几百页长章节下是 OOM 的诱因之一。
  static final _smbReadSemaphore = _Semaphore(2);

  /// SMB 页磁盘缓存有效期：7 天（漫画页不会变，长有效期才能让"回头翻"命中）。
  static const _smbPageCacheDuration = 7 * 24 * 60 * 60 * 1000;

  /// 读取一页 SMB 图片的字节（**只取字节，不解码**）。
  ///
  /// 顺序：磁盘缓存命中 ⇒ 直接返回；未命中 ⇒ 信号量包裹「connect + readFile」并落盘。
  /// [checkStop] 用于在途取消：快速翻页/退出时由 [BaseImageProvider] 判定本次加载已作废，
  /// 在连接前与读取后各判一次，避免白占 SMB 连接。
  static Future<Uint8List> _readSmbPage(
    String imageKey,
    String cacheKey,
    void Function()? checkStop,
  ) async {
    final cached = await CacheManager().findCache(cacheKey);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      if (bytes.isNotEmpty) {
        return Uint8List.fromList(bytes);
      }
    }

    checkStop?.call();

    final config = parseSmbConfigFromUrl(imageKey);
    final remotePath = smbPathFromUrl(imageKey);

    await _smbReadSemaphore.acquire();
    try {
      final client = SmbClient(config: config);
      late final Uint8List data;
      try {
        await client.connect();
        data = await client.readFile(remotePath);
        if (data.isEmpty) {
          throw "Error: Empty response body.";
        }
      } catch (e) {
        // 只有真正的读取失败才算"失败日志"（判停走的是另一条路径，不会到这里）。
        Log.error('SMB Reader', e);
        rethrow;
      } finally {
        await client.disconnect();
      }
      // ⭐ 先落盘再判停：即便本页已被判停，字节也进了缓存，
      // 下次进入该页直接命中 ⇒ 正是本次修复要的"不再闪烁"。
      await CacheManager().writeCache(cacheKey, data, _smbPageCacheDuration);
      checkStop?.call();
      return data;
    } finally {
      _smbReadSemaphore.release();
    }
  }

  /// ⭐ 新增（2026-10-24）：SMB 页「落盘预取」—— 后台把该页字节读进磁盘缓存，**不解码**。
  ///
  /// 供 `pages/reader/images.dart` 的 `_preDownloadImage` 调用：这是"预加载图片数量"
  /// 对 SMB 该有的语义（备好字节，不占解码内存）。并发由 [_smbReadSemaphore] 兜住。
  /// 预取只是优化，失败必须静默（不能影响阅读）。
  static Future<void> prefetchSmbPage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) async {
    if (!imageKey.startsWith('smb://')) {
      return;
    }
    try {
      await _readSmbPage(imageKey, "$imageKey@$sourceKey@$cid@$eid", null);
    } catch (_) {
      // 静默：目标页可能不在、或 NAS 暂时不可达，正常翻到该页时再走一次即可。
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
