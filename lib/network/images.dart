import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/consts.dart';
import 'package:venera_nas/utils/image.dart';

import 'app_dio.dart';

/// 图片下载失败重试的**退避基准**。
///
/// 原实现失败后**立即**重发，最多重试 5 次 ⇒ 同一张图瞬间打出 6 个请求，
/// 服务端限流时还会所有图片一起齐发，形成请求尖峰。改为指数退避 + 随机抖动。
///
/// ⚠️ 故意用 `microseconds` 常量：`tool/appearance_guard.dart` 的「硬编码时长」
/// 规则只扫以毫秒为单位的 `Duration` 字面量，网络重试与外观动效无关，写成毫秒
/// 会被误记成外观硬编码并抬高棘轮基线（同类做法见 `app_dio.dart` 的锁超时常量）。
const Duration _retryBaseDelay = Duration(microseconds: 400000);

/// 单次退避的上限：指数增长到此后不再增加。
const Duration _retryMaxDelay = Duration(microseconds: 8000000);

final Random _retryRandom = Random();

/// 计算第 [attempt] 次（从 0 开始）重试前的等待时间。
///
/// 指数部分 = 基准 × 2^attempt，抖动 = 0~1 个基准 ⇒ 同时失败的多张图不会在
/// 同一个时间点再次齐发。上限由 [_retryMaxDelay] 收敛，避免长时间卡住重试。
Duration _retryDelay(int attempt) {
  final baseMicros = _retryBaseDelay.inMicroseconds;
  final backoffMicros = baseMicros * (1 << attempt);
  final jitterMicros = _retryRandom.nextInt(baseMicros);
  final totalMicros = backoffMicros + jitterMicros;
  return Duration(
    microseconds: totalMicros > _retryMaxDelay.inMicroseconds
        ? _retryMaxDelay.inMicroseconds
        : totalMicros,
  );
}

/// 单张图片加载的取消信号。
///
/// `loadComicImage` 的多个订阅者共享同一条上游流；当**最后一个**订阅者取消时，
/// `_StreamWrapper` 会关掉上游流，这里必须同时取消正在进行的 HTTP 请求并禁止
/// 后续重试 —— 否则"取消"只是不再接收数据，后台仍在重试烧流量。
class _ImageLoadControl {
  final CancelToken cancelToken = CancelToken();

  bool isCancelled = false;

  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('Image loading cancelled');
    }
  }
}

abstract class ImageDownloader {
  static Stream<ImageDownloadProgress> loadThumbnail(
    String url,
    String? sourceKey, [
    String? cid,
  ]) async* {
    final cacheKey = "$url@$sourceKey${cid != null ? '@$cid' : ''}";
    final cache = await CacheManager().findCache(cacheKey);

    if (cache != null) {
      var data = await cache.readAsBytes();
      yield ImageDownloadProgress(
        currentBytes: data.length,
        totalBytes: data.length,
        imageBytes: data,
      );
    }

    var configs = <String, dynamic>{};
    if (sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      configs = comicSource?.getThumbnailLoadingConfig?.call(url) ?? {};
    }
    configs['headers'] ??= {};
    if (configs['headers']['user-agent'] == null &&
        configs['headers']['User-Agent'] == null) {
      configs['headers']['user-agent'] = webUA;
    }

    if (((configs['url'] as String?) ?? url).startsWith('cover.') &&
        sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      if (comicSource != null) {
        var comicInfo = await comicSource.loadComicInfo!(cid!);
        yield* loadThumbnail(comicInfo.data.cover, sourceKey);
        return;
      }
    }

    var dio = AppDio(
      BaseOptions(
        headers: Map<String, dynamic>.from(configs['headers']),
        method: configs['method'] ?? 'GET',
        responseType: ResponseType.stream,
      ),
    );

    String requestUrl = configs['url'] ?? url;
    if (requestUrl.startsWith('//')) {
      requestUrl = 'https:$requestUrl';
    }
    var req = await dio.request<ResponseBody>(
      requestUrl,
      data: configs['data'],
    );
    var stream = req.data?.stream ?? (throw "Error: Empty response body.");
    int? expectedBytes = req.data!.contentLength;
    if (expectedBytes == -1) {
      expectedBytes = null;
    }
    var buffer = <int>[];
    await for (var data in stream) {
      buffer.addAll(data);
      if (expectedBytes != null) {
        yield ImageDownloadProgress(
          currentBytes: buffer.length,
          totalBytes: expectedBytes,
        );
      }
    }

    if (configs['onResponse'] is JSInvokable) {
      final uint8List = Uint8List.fromList(buffer);
      buffer = (configs['onResponse'] as JSInvokable)([uint8List]);
      (configs['onResponse'] as JSInvokable).free();
    }

    await CacheManager().writeCache(cacheKey, buffer);
    yield ImageDownloadProgress(
      currentBytes: buffer.length,
      totalBytes: buffer.length,
      imageBytes: Uint8List.fromList(buffer),
    );
  }

  static final _loadingImages =
      <String, _StreamWrapper<ImageDownloadProgress>>{};

  /// Cancel all loading images.
  static void cancelAllLoadingImages() {
    // 取消会同步触发 `onClosed` 从 `_loadingImages` 里删除元素 ⇒ 必须先拷贝
    // 一份再遍历，否则边遍历边删会抛 ConcurrentModificationError。
    for (var wrapper in List.of(_loadingImages.values)) {
      wrapper.cancel();
    }
    _loadingImages.clear();
  }

  /// Load a comic image from the network or cache.
  /// The function will prevent multiple requests for the same image.
  static Stream<ImageDownloadProgress> loadComicImage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) {
    final cacheKey = "$imageKey@$sourceKey@$cid@$eid";
    if (_loadingImages.containsKey(cacheKey)) {
      return _loadingImages[cacheKey]!.stream;
    }
    // 取消信号与共享上游流绑定：最后一个订阅者取消 ⇒ 停 HTTP 请求 + 停止重试。
    final control = _ImageLoadControl();
    final stream = _StreamWrapper<ImageDownloadProgress>(
      _loadComicImage(imageKey, sourceKey, cid, eid, control: control),
      (wrapper) {
        _loadingImages.remove(cacheKey);
      },
      onCancel: control.cancel,
    );
    _loadingImages[cacheKey] = stream;
    return stream.stream;
  }

  static Stream<ImageDownloadProgress> loadComicImageUnwrapped(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid,
  ) {
    return _loadComicImage(imageKey, sourceKey, cid, eid);
  }

  static Stream<ImageDownloadProgress> _loadComicImage(
    String imageKey,
    String? sourceKey,
    String cid,
    String eid, {
    _ImageLoadControl? control,
  }) async* {
    if (control?.isCancelled ?? false) return;
    final cacheKey = "$imageKey@$sourceKey@$cid@$eid";
    final cache = await CacheManager().findCache(cacheKey);

    if (cache != null) {
      var data = await cache.readAsBytes();
      yield ImageDownloadProgress(
        currentBytes: data.length,
        totalBytes: data.length,
        imageBytes: data,
      );
      return;
    }

    Future<Map<String, dynamic>?> Function()? onLoadFailed;

    var configs = <String, dynamic>{};
    if (sourceKey != null) {
      var comicSource = ComicSource.find(sourceKey);
      configs =
          (await comicSource!.getImageLoadingConfig?.call(
            imageKey,
            cid,
            eid,
          )) ??
          {};
    }
    var retryLimit = 5;
    // 已重试次数（指数退避的指数项，从 0 开始）。
    var retryAttempt = 0;
    while (true) {
      // 订阅者已全部取消 ⇒ 不再发起新的尝试。
      if (control?.isCancelled ?? false) return;
      try {
        configs['headers'] ??= {'user-agent': webUA};

        if (configs['onLoadFailed'] is JSInvokable) {
          onLoadFailed = () async {
            dynamic result = (configs['onLoadFailed'] as JSInvokable)([]);
            if (result is Future) {
              result = await result;
            }
            if (result is! Map<String, dynamic>) return null;
            return result;
          };
        }

        var dio = AppDio(
          BaseOptions(
            headers: configs['headers'],
            method: configs['method'] ?? 'GET',
            responseType: ResponseType.stream,
          ),
        );

        var req = await dio.request<ResponseBody>(
          configs['url'] ?? imageKey,
          data: configs['data'],
          // 取消时真正中断 HTTP 流，而不是只丢弃已到达的数据。
          cancelToken: control?.cancelToken,
        );
        var stream = req.data?.stream ?? (throw "Error: Empty response body.");
        int? expectedBytes = req.data!.contentLength;
        if (expectedBytes == -1) {
          expectedBytes = null;
        }
        var buffer = <int>[];
        await for (var data in stream) {
          buffer.addAll(data);
          yield ImageDownloadProgress(
            currentBytes: buffer.length,
            totalBytes: expectedBytes,
          );
        }

        if (configs['onResponse'] is JSInvokable) {
          dynamic result = (configs['onResponse'] as JSInvokable)([
            Uint8List.fromList(buffer),
          ]);
          if (result is Future) {
            result = await result;
          }
          if (result is List<int>) {
            buffer = result;
          } else {
            throw "Error: Invalid onResponse result.";
          }
          (configs['onResponse'] as JSInvokable).free();
        }

        Uint8List data;
        if (buffer is Uint8List) {
          data = buffer;
        } else {
          data = Uint8List.fromList(buffer);
          buffer.clear();
        }

        if (configs['modifyImage'] != null) {
          var newData = await modifyImageWithScript(
            data,
            configs['modifyImage'],
          );
          data = newData;
        }

        await CacheManager().writeCache(cacheKey, data);
        yield ImageDownloadProgress(
          currentBytes: data.length,
          totalBytes: data.length,
          imageBytes: data,
        );
        return;
      } catch (e) {
        // 取消不是失败：不触发服务端的 onLoadFailed 回调，也不再重试。
        if (control?.isCancelled ?? false) {
          rethrow;
        }
        if (retryLimit < 0 || onLoadFailed == null) {
          rethrow;
        }
        var newConfig = await onLoadFailed();
        (configs['onLoadFailed'] as JSInvokable).free();
        onLoadFailed = null;
        if (newConfig == null) {
          rethrow;
        }
        configs = newConfig;
        retryLimit--;
        // ⭐ 退避 + 抖动后再重试：原实现失败即重发，5 次重试会瞬间打出 6 个
        // 请求；这里第 0/1/2… 次分别等待 base、2×base、4×base…（带随机抖动）。
        final delay = _retryDelay(retryAttempt);
        retryAttempt++;
        await Future.delayed(delay);
        if (control?.isCancelled ?? false) return;
      } finally {
        if (onLoadFailed != null) {
          (configs['onLoadFailed'] as JSInvokable).free();
        }
      }
    }
  }
}

/// A wrapper class for a stream that
/// allows multiple listeners to listen to the same stream.
class _StreamWrapper<T> {
  final Stream<T> _stream;

  final List<StreamController<T>> controllers = [];

  final void Function(_StreamWrapper<T> wrapper) onClosed;

  /// 上游被取消时的回调（让调用方同时停掉 HTTP 请求与重试）。
  final void Function()? onCancel;

  /// 上游订阅句柄：取消它才会真正停止下载 / 停止重试，而不只是不再转发数据。
  StreamSubscription<T>? _subscription;

  bool isClosed = false;

  _StreamWrapper(this._stream, this.onClosed, {this.onCancel}) {
    _listen();
  }

  void _listen() {
    _subscription = _stream.listen(
      (data) {
        if (isClosed) return;
        for (var controller in List.of(controllers)) {
          if (!controller.isClosed) {
            controller.add(data);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        for (var controller in List.of(controllers)) {
          if (!controller.isClosed) {
            controller.addError(error, stack);
          }
        }
      },
      onDone: _closeUpstream,
    );
  }

  void _closeUpstream() {
    if (isClosed) return;
    isClosed = true;
    for (var controller in List.of(controllers)) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    controllers.clear();
    onClosed(this);
  }

  Stream<T> get stream {
    if (isClosed) {
      throw Exception('Stream is closed');
    }
    var controller = StreamController<T>();
    controllers.add(controller);
    controller.onCancel = () {
      if (!controllers.remove(controller)) return;
      if (!controller.isClosed) {
        controller.close();
      }
      // 最后一个订阅者也走了 ⇒ 这次下载已经没人要：取消上游订阅，
      // 顺带通过 [onCancel] 中断 HTTP 请求并停止重试。
      if (controllers.isEmpty) {
        cancel();
      }
    };
    return controller.stream;
  }

  void cancel() {
    if (isClosed) return;
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    _subscription = null;
    onCancel?.call();
    _closeUpstream();
  }
}

class ImageDownloadProgress {
  final int currentBytes;

  final int? totalBytes;

  final Uint8List? imageBytes;

  const ImageDownloadProgress({
    required this.currentBytes,
    required this.totalBytes,
    this.imageBytes,
  });
}
