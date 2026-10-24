import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/app_dio.dart';

class NetworkCache {
  final Uri uri;

  final Map<String, dynamic> requestHeaders;

  final Map<String, List<String>> responseHeaders;

  final Object? data;

  /// 响应时间（用于判断缓存是否新鲜，语义不变）。
  final DateTime time;

  /// 最近一次被命中的时间（LRU 淘汰依据）。
  ///
  /// 与 [time] 分开：`time` 判断"内容是否过期"，`lastAccess` 判断"该淘汰谁"。
  /// 淘汰必须按最近访问时间，不能按插入顺序（FIFO 会把仍在反复使用的热数据踢掉）。
  DateTime lastAccess;

  final int size;

  NetworkCache({
    required this.uri,
    required this.requestHeaders,
    required this.responseHeaders,
    required this.data,
    required this.time,
    required this.size,
    DateTime? lastAccess,
  }) : lastAccess = lastAccess ?? DateTime.now();
}

class NetworkCacheManager implements Interceptor {
  NetworkCacheManager._();

  static final NetworkCacheManager instance = NetworkCacheManager._();

  factory NetworkCacheManager() => instance;

  /// 缓存键 = 完整 URI + **身份指纹**。
  ///
  /// 原实现只用 URI 当键，而 `compareHeaders` 又把 `authorization` / `token` /
  /// `cookie` 等身份头列入忽略表 ⇒ 同一 URL 在**多账号**下会互相命中对方的响应
  /// （账号 A 的私有数据被账号 B 读到）。现在把身份头做稳定 hash 拼进键，
  /// 不同身份天然落到不同槽位，忽略表只影响"同身份内是否算同一请求"。
  final Map<String, NetworkCache> _cache = {};

  int size = 0;

  /// 参与身份指纹的请求头（大小写不敏感）。
  static const _identityHeaders = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'token',
    'x-token',
    'x-auth-token',
    'x-access-token',
    'x-api-key',
    'api-key',
  };

  /// 对身份相关请求头做**稳定** hash（用 `sha256` 而不是 `Object.hashCode`：
  /// Dart 的 `hashCode` 不保证跨进程/跨启动稳定，不能用作跨会话身份凭据）。
  static String identityFingerprint(Map<String, dynamic> headers) {
    final parts = <String>[];
    headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (_identityHeaders.contains(lower)) {
        parts.add('$lower=$value');
      }
    });
    // 排序保证 header 顺序不同但内容相同时得到同一个指纹。
    parts.sort();
    return sha256
        .convert(utf8.encode(parts.join('\n')))
        .toString()
        .substring(0, 16);
  }

  /// 把 URI 与身份指纹拼成内部缓存键（`\u0000` 分隔，避免拼接歧义）。
  static String _cacheKey(Uri uri, Map<String, dynamic> headers) {
    return '${uri.toString()}\u0000${identityFingerprint(headers)}';
  }

  NetworkCache? getCache(Uri uri, {Map<String, dynamic>? requestHeaders}) {
    final cache = _cache[_cacheKey(uri, requestHeaders ?? const {})];
    if (cache == null) {
      return null;
    }
    // 命中即刷新最近访问时间 ⇒ 淘汰按"最近最少使用"而不是"最早写入"。
    cache.lastAccess = DateTime.now();
    return cache;
  }

  static const _maxCacheSize = 10 * 1024 * 1024;

  void setCache(NetworkCache cache) {
    final key = _cacheKey(cache.uri, cache.requestHeaders);
    final replaced = _cache.remove(key);
    if (replaced != null) {
      size -= replaced.size;
    }
    // 先按最近访问时间腾出空间再写入（原实现是"先while后写"，且用插入顺序
    // 取 `_cache.values.first` ⇒ FIFO，且缓存为空时会抛 StateError）。
    while (_cache.isNotEmpty && size + cache.size > _maxCacheSize) {
      _evictLeastRecentlyUsed();
    }
    _cache[key] = cache;
    size += cache.size;
  }

  /// 淘汰最近最少使用的条目。
  void _evictLeastRecentlyUsed() {
    MapEntry<String, NetworkCache>? oldest;
    for (final entry in _cache.entries) {
      if (oldest == null ||
          entry.value.lastAccess.isBefore(oldest.value.lastAccess)) {
        oldest = entry;
      }
    }
    if (oldest != null) {
      size -= oldest.value.size;
      _cache.remove(oldest.key);
    }
  }

  void removeCache(Uri uri, {Map<String, dynamic>? requestHeaders}) {
    final key = _cacheKey(uri, requestHeaders ?? const {});
    var cache = _cache[key];
    if (cache != null) {
      size -= cache.size;
    }
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
    size = 0;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.method != "GET") {
      return handler.next(err);
    }
    return handler.next(err);
  }

  /// 从缓存构造成功响应（统一入口 ✓：`venera-cache: true` 标记只在 `onResponse` 里被识别 ✓）。
  static Response<dynamic> _cachedResponse(
    RequestOptions options,
    NetworkCache cache,
  ) {
    return Response(
      requestOptions: options,
      data: cache.data,
      headers: Headers.fromMap(cache.responseHeaders)
        ..set('venera-cache', 'true'),
      statusCode: 200,
    );
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.method != "GET") {
      return handler.next(options);
    }
    var cache = getCache(options.uri, requestHeaders: options.headers);
    if (cache == null ||
        !compareHeaders(options.headers, cache.requestHeaders)) {
      if (options.headers['cache-time'] != null) {
        options.headers.remove('cache-time');
      }
      return handler.next(options);
    } else {
      if (options.headers['cache-time'] == 'no') {
        options.headers.remove('cache-time');
        removeCache(options.uri, requestHeaders: options.headers);
        return handler.next(options);
      }
    }
    // ⭐ 修复（2026-10-24）：本方法虽是 `async void`（dio 的接口签名如此 ✓），
    // 但**任何异常都必须交还一次控制权** ✗ —— 原先 HEAD 校验没有 try/catch，
    // 断网 / 超时 / 服务端不支持 HEAD 时异常逃逸 ⇒ `handler` 永不回调 ⇒ **请求永久挂起** ✗。
    final cached = cache;
    try {
      var time = DateTime.now();
      var diff = time.difference(cached.time);
      if (options.headers['cache-time'] == 'long' &&
          diff < const Duration(hours: 6)) {
        return handler.resolve(_cachedResponse(options, cached));
      } else if (diff < const Duration(seconds: 5)) {
        return handler.resolve(_cachedResponse(options, cached));
      } else if (diff < const Duration(hours: 2)) {
        var o = options.copyWith(method: "HEAD");
        var dio = AppDio();
        Response response;
        try {
          response = await dio.fetch(o);
        } catch (e, s) {
          // 校验请求失败（断网 / 超时 / 服务端不支持 HEAD ✓）⇒ **回退缓存** ✓：
          // 可用性优先 —— 有缓存就先用缓存 ✓；缓存保留，下次请求再重新校验 ✓。
          Log.error("NetworkCache", "HEAD validation failed, use cache: $e", s);
          return handler.resolve(_cachedResponse(options, cached));
        }
        if (response.statusCode == 200 &&
            compareHeaders(cached.responseHeaders, response.headers.map)) {
          return handler.resolve(_cachedResponse(options, cached));
        }
      }
      removeCache(options.uri, requestHeaders: options.headers);
      return handler.next(options);
    } catch (e, s) {
      // 兜底 ✓：任何未预料异常（含 `compareHeaders` 结构异常 ✓）都不能让请求挂死 ✗。
      Log.error("NetworkCache", "Cache handling failed: $e", s);
      removeCache(options.uri, requestHeaders: options.headers);
      return handler.next(options);
    }
  }

  static bool compareHeaders(Map<String, dynamic> a, Map<String, dynamic> b) {
    a = Map.from(a);
    b = Map.from(b);
    const shouldIgnore = [
      'cache-time',
      'prevent-parallel',
      'date',
      'x-varnish',
      'cf-ray',
      'connection',
      'vary',
      'content-encoding',
      'report-to',
      'server-timing',
      'token',
      'set-cookie',
      'cf-cache-status',
      'cf-request-id',
      'cf-ray',
      'authorization',
    ];
    for (var key in shouldIgnore) {
      a.remove(key);
      b.remove(key);
    }
    if (a.length != b.length) {
      return false;
    }
    for (var key in a.keys) {
      if (a[key] is List && b[key] is List) {
        if (a[key].length != b[key].length) {
          return false;
        }
        for (var i = 0; i < a[key].length; i++) {
          if (a[key][i] != b[key][i]) {
            return false;
          }
        }
      } else if (a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (response.requestOptions.method != "GET") {
      return handler.next(response);
    }
    if (response.statusCode != null && response.statusCode! >= 400) {
      return handler.next(response);
    }
    var size = _calculateSize(response.data);
    if (size != null && size < 1024 * 1024 && size > 0) {
      var cache = NetworkCache(
        uri: response.requestOptions.uri,
        requestHeaders: response.requestOptions.headers,
        responseHeaders: Map.from(response.headers.map),
        data: response.data,
        time: DateTime.now(),
        size: size,
      );
      setCache(cache);
    }
    handler.next(response);
  }

  static int? _calculateSize(Object? data) {
    if (data == null) {
      return 0;
    }
    if (data is List<int>) {
      return data.length;
    }
    if (data is Uint8List) {
      return data.length;
    }
    if (data is String) {
      if (data.trim().isEmpty) {
        return 0;
      }
      if (data.length < 512 && data.contains("IP address")) {
        return 0;
      }
      return data.length * 4;
    }
    if (data is Map) {
      return data.toString().length * 4;
    }
    return null;
  }
}
