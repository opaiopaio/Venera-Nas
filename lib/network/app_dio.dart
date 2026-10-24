import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/cache.dart';
import 'package:venera_nas/network/proxy.dart';

import '../foundation/app.dart';
import 'cloudflare.dart';
import 'cookie_jar.dart';

export 'package:dio/dio.dart';

class MyLogInterceptor implements Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Log.error(
      "Network",
      "${err.requestOptions.method} ${err.requestOptions.path}\n$err\n${err.response?.data.toString()}",
    );
    switch (err.type) {
      case DioExceptionType.badResponse:
        var statusCode = err.response?.statusCode;
        if (statusCode != null) {
          err = err.copyWith(
            message:
                "Invalid Status Code: $statusCode. "
                "${_getStatusCodeInfo(statusCode)}",
          );
        }
      case DioExceptionType.connectionTimeout:
        err = err.copyWith(message: "Connection Timeout");
      case DioExceptionType.receiveTimeout:
        err = err.copyWith(
          message:
              "Receive Timeout: "
              "This indicates that the server is too busy to respond",
        );
      case DioExceptionType.unknown:
        if (err.toString().contains("Connection terminated during handshake")) {
          err = err.copyWith(
            message:
                "Connection terminated during handshake: "
                "This may be caused by the firewall blocking the connection "
                "or your requests are too frequent.",
          );
        } else if (err.toString().contains("Connection reset by peer")) {
          err = err.copyWith(
            message:
                "Connection reset by peer: "
                "The error is unrelated to app, please check your network.",
          );
        }
      default:
        {}
    }
    handler.next(err);
  }

  static const errorMessages = <int, String>{
    400: "The Request is invalid.",
    401: "The Request is unauthorized.",
    403: "No permission to access the resource. Check your account or network.",
    404: "Not found.",
    429: "Too many requests. Please try again later.",
  };

  String _getStatusCodeInfo(int? statusCode) {
    if (statusCode != null && statusCode >= 500) {
      return "This is server-side error, please try again later. "
          "Do not report this issue.";
    } else {
      return errorMessages[statusCode] ?? "";
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    var headers = response.headers.map.map(
      (key, value) => MapEntry(
        key.toLowerCase(),
        value.length == 1 ? value.first : value.toString(),
      ),
    );
    headers.remove("cookie");
    String content;
    if (response.data is List<int>) {
      try {
        content = utf8.decode(response.data, allowMalformed: false);
      } catch (e) {
        content = "<Bytes>\nlength:${response.data.length}";
      }
    } else {
      content = response.data.toString();
    }
    Log.addLog(
      (response.statusCode != null && response.statusCode! < 400)
          ? LogLevel.info
          : LogLevel.error,
      "Network",
      "Response ${response.realUri.toString()} ${response.statusCode}\n"
          "headers:\n$headers\n$content",
    );
    handler.next(response);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    const String headerMask = "********";
    const String dataMask = "****** DATA_PROTECTED ******";
    Log.info(
      "Network",
      "${options.method} ${options.uri}\n"
          "headers:\n${options.extra.containsKey("maskHeadersInLog") ? options.headers.map((key, value) => MapEntry(key, options.extra["maskHeadersInLog"].contains(key) ? headerMask : value)) : options.headers}\n"
          "data:\n${options.extra["maskDataInLog"] == true ? dataMask : options.data}",
    );
    options.connectTimeout = const Duration(seconds: 15);
    options.receiveTimeout = const Duration(seconds: 15);
    options.sendTimeout = const Duration(seconds: 15);
    handler.next(options);
  }
}

class AppDio with DioMixin {
  /// 无自定义 [BaseOptions] 时复用同一个默认客户端。
  ///
  /// 原因：默认配置的客户端没有实例级可变状态（拦截器都是单例 / 共享 cookie jar，
  /// adapter 也只读全局设置），但每次构造都会重建一份拦截器链与 rhttp adapter；
  /// 缓存 HEAD 校验、漫画源更新检查等高频路径会反复 `new`。
  ///
  /// ⚠️ 只在 `App.isInitialized` 之后缓存：初始化前构造的实例拿不到
  /// cookie / 缓存 / Cloudflare 拦截器，若被后续复用会造成这些能力永久缺失。
  ///
  /// ⚠️ 拿到的是共享实例：**不要修改它的 `options`**（baseUrl / 默认 headers 等），
  /// 需要自定义配置时请显式传入 `BaseOptions`，这样会得到独立实例。
  factory AppDio([BaseOptions? options]) {
    if (options == null && App.isInitialized) {
      return _shared ??= AppDio._(null);
    }
    return AppDio._(options);
  }

  AppDio._(BaseOptions? options) {
    this.options = options ?? BaseOptions();
    httpClientAdapter = RHttpAdapter();
    if (App.isInitialized) {
      interceptors.add(CookieManagerSql(SingleInstanceCookieJar.instance!));
      interceptors.add(NetworkCacheManager());
      interceptors.add(CloudflareInterceptor());
      interceptors.add(MyLogInterceptor());
    }
  }

  /// 默认客户端单例（仅 [App.isInitialized] 后才会被创建）。
  static AppDio? _shared;

  /// `prevent-parallel` 锁 ✓：key = path，value = **持有者 token** ✓。
  ///
  /// ⭐ 修复（2026-10-24）：原实现是 `Map<String, bool>` ✗ ——
  /// ① `finally` 里只判断 `containsKey` 就 remove ⇒ **没加锁的请求也会删掉别人的锁** ✗；
  /// ② 两个等待者会同时看到"锁没了"并同时拿到锁 ✗。
  /// 现在用 token 标识持有者，只有持有者自己才释放 ✓。
  static final Map<String, Object> _requests = {};

  /// 等锁上限 ✓：原实现 20ms 轮询**没有超时** ⇒ 持锁请求卡住时等待方永久挂起 ✗。
  static const Duration _lockTimeout = Duration(microseconds: 30000000);

  static const Duration _lockPollInterval = Duration(microseconds: 20000);

  @override
  Future<Response<T>> request<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    Object? lockToken;
    if (options?.headers?['prevent-parallel'] == 'true') {
      // 这个头只给本方法用 ✓：绝不能带到服务端 ✓。
      options!.headers!.remove('prevent-parallel');
      final token = Object();
      final deadline = DateTime.now().add(_lockTimeout);
      while (true) {
        // 等锁期间也要能被取消 ✓：否则调用方已经 cancel 了，这里还在一遍遍轮询 ✗。
        final cancelError = cancelToken?.cancelError;
        if (cancelError != null) {
          throw cancelError;
        }
        if (!_requests.containsKey(path)) {
          _requests[path] = token;
          lockToken = token;
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw DioException(
            requestOptions: RequestOptions(path: path),
            type: DioExceptionType.unknown,
            message:
                "Waiting for the previous request to $path timed out "
                "after ${_lockTimeout.inSeconds}s",
          );
        }
        await Future.delayed(_lockPollInterval);
      }
    }
    try {
      // ⚠️ 必须 `await` ✓：`return super.request(...)` 会让 finally 在请求真正完成
      // **之前**就释放锁 ✗（async 函数 return 一个 Future 时 finally 立即执行 ✓）。
      return await super.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        options: options,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
    } finally {
      // 只有持有者能释放 ✓：等待中抛错（取消 / 超时）时 lockToken 仍为 null ⇒ 不会误删 ✓。
      if (lockToken != null && identical(_requests[path], lockToken)) {
        _requests.remove(path);
      }
    }
  }
}

class RHttpAdapter implements HttpClientAdapter {
  final bool enableProxy;

  RHttpAdapter({this.enableProxy = true});

  Future<rhttp.ClientSettings> get settings async {
    var proxy = enableProxy ? await getProxy() : null;

    return rhttp.ClientSettings(
      proxySettings: proxy == null
          ? const rhttp.ProxySettings.noProxy()
          : rhttp.ProxySettings.proxy(proxy),
      redirectSettings: const rhttp.RedirectSettings.limited(5),
      timeoutSettings: const rhttp.TimeoutSettings(
        connectTimeout: Duration(seconds: 15),
        keepAliveTimeout: Duration(seconds: 60),
        keepAlivePing: Duration(seconds: 30),
      ),
      throwOnStatusCode: false,
      dnsSettings: rhttp.DnsSettings.static(overrides: _getOverrides()),
      tlsSettings: rhttp.TlsSettings(
        sni: appdata.settings['sni'] != false,
        verifyCertificates: appdata.settings['ignoreBadCertificate'] != true,
      ),
    );
  }

  static Map<String, List<String>> _getOverrides() {
    if (!appdata.settings['enableDnsOverrides'] == true) {
      return {};
    }
    var config = appdata.settings["dnsOverrides"];
    var result = <String, List<String>>{};
    if (config is Map) {
      for (var entry in config.entries) {
        if (entry.key is String && entry.value is String) {
          result[entry.key] = [entry.value];
        }
      }
    }
    return result;
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.headers['User-Agent'] == null &&
        options.headers['user-agent'] == null) {
      options.headers['User-Agent'] = "venera/v${App.version}";
    }

    var res = await rhttp.Rhttp.request(
      method: rhttp.HttpMethod(options.method),
      url: options.uri.toString(),
      settings: await settings,
      expectBody: rhttp.HttpExpectBody.stream,
      body: requestStream == null ? null : rhttp.HttpBody.stream(requestStream),
      headers: rhttp.HttpHeaders.rawMap(
        Map.fromEntries(
          options.headers.entries.map(
            (e) => MapEntry(e.key, e.value.toString().trim()),
          ),
        ),
      ),
    );
    if (res is! rhttp.HttpStreamResponse) {
      throw Exception("Invalid response type: ${res.runtimeType}");
    }
    var headers = <String, List<String>>{};
    for (var entry in res.headers) {
      var key = entry.$1.toLowerCase();
      headers[key] ??= [];
      headers[key]!.add(entry.$2);
    }
    return ResponseBody(
      res.body,
      res.statusCode,
      statusMessage: _getStatusMessage(res.statusCode),
      isRedirect: false,
      headers: headers,
    );
  }

  static String _getStatusMessage(int statusCode) {
    return switch (statusCode) {
      200 => "OK",
      201 => "Created",
      202 => "Accepted",
      204 => "No Content",
      206 => "Partial Content",
      301 => "Moved Permanently",
      302 => "Found",
      400 => "Invalid Status Code 400: The Request is invalid.",
      401 => "Invalid Status Code 401: The Request is unauthorized.",
      403 =>
        "Invalid Status Code 403: No permission to access the resource. Check your account or network.",
      404 => "Invalid Status Code 404: Not found.",
      429 =>
        "Invalid Status Code 429: Too many requests. Please try again later.",
      _ => "Invalid Status Code $statusCode",
    };
  }
}
