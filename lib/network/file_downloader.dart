import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/io.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/app_dio.dart';
import 'package:venera_nas/network/proxy.dart';
import 'package:venera_nas/utils/ext.dart';

class FileDownloader {
  final String url;
  final String savePath;
  final int maxConcurrent;

  FileDownloader(this.url, this.savePath, {this.maxConcurrent = 4});

  int _currentBytes = 0;

  int _lastBytes = 0;

  late int _fileSize;

  /// 服务端 ETag ✓：用于判断断点状态是否属于**同一个远端文件** ✓。
  String? _etag;

  /// ⭐ 修复（2026-10-24）：Dio 必须配置连接 / 接收超时 ✓ ——
  /// 原实现两个超时都是 null ✗ ⇒ HEAD 或分块 GET 只要"连接建立但服务端不回数据"，
  /// 就会**永久挂起** ✓，`stop()` 也只置标志位、打断不了 ✗。
  /// 现在 30s 建连、60s 收不到新数据就抛 `DioException` ✓，交给上层重试 / 收尾 ✓。
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(microseconds: 30000000),
      receiveTimeout: const Duration(microseconds: 60000000),
    ),
  );

  /// 全局取消令牌 ✓：`stop()` 直接打断在途 HEAD ✓，并转发给每个分块请求的
  /// 子令牌 ✓（见 [_newRequestToken]）—— 单个块响应不合法时也能只取消这一条连接 ✓。
  final _cancelToken = CancelToken();

  RandomAccessFile? _file;

  bool _isWriting = false;

  int _kChunkSize = 16 * 1024 * 1024;

  bool _canceled = false;

  /// 单块重试上限 ✓：只对"206 / Content-Range 校验失败"这类可重试错误生效 ✓。
  static const int _maxBlockRetry = 3;

  /// `Content-Range: bytes 0-1023/4096` ✓（`*` 总长不算合法 206 响应 ✓）。
  static final _contentRangePattern = RegExp(
    r'^\s*bytes\s+(\d+)-(\d+)/(\d+)\s*$',
    caseSensitive: false,
  );

  late List<_DownloadBlock> _blocks;

  Future<void> _writeStatus() async {
    var file = File("$savePath.download");
    // ⭐ 修复（2026-10-24）：断点状态必须带上**任务身份**（url / 文件长度 / ETag）✓ ——
    // 原实现只存块进度 ✗ ⇒ 同一 savePath 换成别的 url、或远端文件长度变了，
    // 旧块会被直接复用 ⇒ "残缺被当成已完成" ✗（`_currentBytes >= _fileSize` 提前成立 ✓）。
    await file.writeAsString(
      jsonEncode({
        "url": url,
        "size": _fileSize,
        "etag": _etag,
        "blocks": _blocks.map((e) => e.toString()).toList(),
      }),
    );
  }

  /// 读取断点状态并校验 ✓。
  ///
  /// 只要 url / 长度 / ETag / 块边界 / **数据文件本身**有任何一处不匹配
  /// （含旧版纯文本格式 ✓），就视为**不可信**：清掉状态文件并返回 false ✓，
  /// 让调用方从头下载 ✓。
  ///
  /// ⭐ 修复（2026-10-24）：状态文件必须与**数据文件成对校验** ✓ ——
  /// 原先只信 `.download` 里的块进度 ✗ ⇒ 数据文件被删 / 被别的东西截断时，
  /// `_prepareFile` 会补一个全 0 的等长文件，而块进度仍显示"已完成" ⇒
  /// **残缺被当成成功** ✗。现在数据文件不存在或长度不符就丢弃状态 ✓。
  Future<bool> _tryReadStatus() async {
    var file = File("$savePath.download");
    if (!await file.exists()) {
      return false;
    }
    try {
      var decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException("download status is not an object");
      }
      if (decoded["url"] != url ||
          decoded["size"] != _fileSize ||
          decoded["blocks"] is! List) {
        throw const FormatException("download status does not match this task");
      }
      // ETag 是"远端文件是否同一份"的最强证据 ✓：这次 HEAD 拿到的 ETag 必须与
      // 状态文件里记录的**完全一致**（含"从有到无 / 从无到有"✓）；不一致就重下 ✓
      // —— 宁可多下一次，也不能把另一个版本的文件片段拼进来 ✗。
      if (decoded["etag"] != _etag) {
        throw const FormatException("remote file changed (etag mismatch)");
      }
      // 数据文件是块进度的**唯一载体** ✓：不存在或长度与远端不一致 ⇒ 状态无效 ✓。
      // （长度应等于 `_fileSize`，因为 `_prepareFile` 一开始就 truncate 到该长度 ✓。）
      final dataFile = File(savePath);
      if (!await dataFile.exists() || await dataFile.length() != _fileSize) {
        throw const FormatException(
          "download payload is missing or has unexpected length",
        );
      }
      final blocks = <_DownloadBlock>[];
      for (final raw in decoded["blocks"] as List) {
        if (raw is! String) {
          throw const FormatException("invalid download block");
        }
        final block = _DownloadBlock.fromString(raw);
        // 块边界必须与本次文件长度自洽 ✓：越界 / 倒序 / 进度超出块长度都不可信 ✓。
        if (block.start < 0 ||
            block.start >= block.end ||
            block.end > _fileSize ||
            block.downloadedBytes < 0 ||
            block.downloadedBytes > block.end - block.start) {
          throw const FormatException("invalid download block range");
        }
        blocks.add(block);
      }
      // 块必须**首尾相接、完整覆盖**整个文件 ✓ —— 只校验区间连续性、不校验块大小 ✓
      //（`_kChunkSize` 会随文件大小变化 ✓）：这样"已完成字节"累加既不会重复也不会漏算，
      // 与数据文件长度（= `_fileSize`）才是同一份文件的进度 ✓。
      if (blocks.isEmpty ||
          blocks.first.start != 0 ||
          blocks.last.end != _fileSize) {
        throw const FormatException("download blocks do not cover the file");
      }
      for (var i = 1; i < blocks.length; i++) {
        if (blocks[i].start != blocks[i - 1].end) {
          throw const FormatException("download blocks are not contiguous");
        }
      }
      _blocks = blocks;
      return true;
    } catch (e) {
      Log.warning("Download", "Discard untrusted download status: $e");
      await _clearStatus();
      return false;
    }
  }

  Future<void> _clearStatus() async {
    var file = File("$savePath.download");
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // 删不掉也不能影响主流程 ✓（下次会因校验失败被再次忽略 ✓）。
      }
    }
  }

  /// 删除数据文件 ✓（失败 / 取消收尾用）。
  ///
  /// ⭐ 修复（2026-10-24）：状态一旦被丢弃，残留 payload 就没有任何续传价值 ✗，
  /// 留着只占磁盘，还会在下一次 `_prepareFile(resume: false)` 时被静默截断 ✓。
  Future<void> _clearPayload() async {
    try {
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 删不掉不影响主流程 ✓（下次从头下载会重新 truncate ✓）。
    }
  }

  /// create file and write empty bytes
  Future<void> _prepareFile({required bool resume}) async {
    var file = File(savePath);
    if (await file.exists()) {
      if (resume && file.lengthSync() == _fileSize) {
        _file = await file.open(mode: FileMode.append);
        return;
      } else {
        await file.delete();
      }
    }

    await file.create(recursive: true);
    _file = await file.open(mode: FileMode.append);
    await _file!.truncate(_fileSize);
  }

  Future<void> _createTasks() async {
    // 每次开始都重置内存进度 ✓：同一个实例被重复 start 时不能继承上一次的块状态 ✗。
    _currentBytes = 0;
    _lastBytes = 0;
    _blocks = [];

    var res = await _dio.head(url, cancelToken: _cancelToken);
    var length = res.headers["content-length"]?.first;
    _fileSize = length == null ? 0 : int.parse(length);
    _etag = res.headers["etag"]?.first;

    // 取消发生在 HEAD 期间 ✓：不能再往下走 —— 否则会去截断 / 重建数据文件，
    // 把上一次 pause 留下的续传进度破坏掉 ✗。
    if (_canceled) return;

    // ⭐ 修复（2026-10-24）：没有合法长度 ⇒ 既不能分块也不能判定完成 ✓。
    // 原实现 `_fileSize = 0` ⇒ `_currentBytes >= _fileSize` 立即成立 ⇒ **空文件被当成下载完成** ✗。
    if (_fileSize <= 0) {
      throw Exception("Missing or invalid Content-Length for $url");
    }

    final canResume = await _tryReadStatus();
    if (_canceled) return;
    await _prepareFile(resume: canResume);

    if (canResume) {
      _currentBytes = _blocks.fold<int>(
        0,
        (previousValue, element) => previousValue + element.downloadedBytes,
      );
    } else {
      if (_fileSize > 1024 * 1024 * 1024) {
        _kChunkSize = 64 * 1024 * 1024;
      } else if (_fileSize > 512 * 1024 * 1024) {
        _kChunkSize = 32 * 1024 * 1024;
      }

      _blocks = [];
      for (var i = 0; i < _fileSize; i += _kChunkSize) {
        var end = i + _kChunkSize;
        if (end > _fileSize) {
          _blocks.add(_DownloadBlock(i, _fileSize, 0, false));
        } else {
          _blocks.add(_DownloadBlock(i, i + _kChunkSize, 0, false));
        }
      }
    }
  }

  Stream<DownloadingStatus> start() {
    var stream = StreamController<DownloadingStatus>();
    _download(stream);
    return stream.stream;
  }

  void _reportStatus(StreamController<DownloadingStatus> stream) {
    stream.add(DownloadingStatus(_currentBytes, _fileSize, 0));
  }

  /// ⭐ 失败收尾（2026-10-24）：关闭文件句柄 + 丢弃 payload 与断点状态 ✓。
  ///
  /// 出错时磁盘上的进度可能只写了一半 ✓ ⇒ 绝不能留给下一次当作断点 ✗。
  Future<void> _setError(
    StreamController<DownloadingStatus> stream,
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    // 先置取消位并取消在途分块请求 ✓：否则其他并发块会继续写"马上要删掉"的文件，
    // 它们抛出的二次异常会盖掉真正的失败原因 / 变成无人监听的异步错误 ✗。
    _canceled = true;
    _cancelInFlight("download failed");
    await _closeFile();
    await _clearStatus();
    await _clearPayload();
    if (!stream.isClosed) {
      stream.addError(error, stackTrace);
      await stream.close();
    }
  }

  /// 取消在途请求 ✓（CancelToken 只允许 cancel 一次，重复 cancel 会打警告日志 ✗）。
  void _cancelInFlight(String reason) {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel(reason);
    }
  }

  /// 安全关闭文件句柄 ✓。
  ///
  /// ⭐ 修复（2026-10-24）：`stop()` 与 `_download` 的收尾路径可能**同时**关同一个
  /// 句柄 ✗（`stop()` 关闭期间 `_file` 还没置空 ✓）⇒ 第二次 close 抛
  /// `FileSystemException: File closed` ✓，而它发生在 catch 里 ⇒ 既盖掉取消、
  /// 又让 `StreamController` 永远不 close ✗。现在先把引用摘掉再关，并吞掉
  /// "已关闭"这类竞态错误 ✓。
  Future<void> _closeFile() async {
    final file = _file;
    _file = null;
    if (file == null) return;
    try {
      await file.close();
    } catch (_) {
      // 并发关闭 / 已被取消打断 ✓：不影响主流程 ✓。
    }
  }

  void _download(StreamController<DownloadingStatus> resultStream) async {
    // ⭐ 2026-10-24：定时上报必须随任务结束一起取消 ✓ ——
    // 原实现只在"下载完成 / 取消"时由 tick 自行 cancel ✗，出错时定时器仍在 ⇒
    // 每秒往**已关闭**的 StreamController 写事件 ⇒ `StateError` 刷屏且永不停止 ✗。
    Timer? timer;
    try {
      var proxy = await getProxy();
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          return HttpClient()
            ..findProxy = (uri) => proxy == null ? "DIRECT" : "PROXY $proxy";
        },
      );

      // get file size
      await _createTasks();

      if (_canceled) {
        // ⭐ 修复（2026-10-24）：取消时同样要**关闭文件句柄并关闭流** ✓ ——
        // 原实现直接 `return` ⇒ `StreamController` 永不 close，监听方永久挂起 ✗。
        await _closeFile();
        await resultStream.close();
        return;
      }

      // check if file is downloaded
      if (_currentBytes >= _fileSize) {
        await _closeFile();
        _reportStatus(resultStream);
        resultStream.close();
        return;
      }

      _reportStatus(resultStream);

      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_canceled || _currentBytes >= _fileSize || resultStream.isClosed) {
          timer.cancel();
          return;
        }
        resultStream.add(
          DownloadingStatus(
            _currentBytes,
            _fileSize,
            _currentBytes - _lastBytes,
          ),
        );
        _lastBytes = _currentBytes;
      });

      // start downloading
      await _scheduleDownload();
      if (_canceled) {
        await _closeFile();
        await resultStream.close();
        return;
      }
      await _closeFile();
      await _clearStatus();

      // check if download is finished
      if (_currentBytes < _fileSize) {
        await _setError(
          resultStream,
          Exception(
            "Download failed: Expected $_fileSize bytes, "
            "but only $_currentBytes bytes downloaded.",
          ),
        );
        return;
      }

      resultStream.add(DownloadingStatus(_currentBytes, _fileSize, 0, true));
      resultStream.close();
    } catch (e, s) {
      if (_canceled) {
        // ⭐ 取消（stop 已关闭文件）会让在途写入抛异常 ✓ —— 这不是下载失败 ✗，
        // 断点状态要保留以便续传 ✓，只负责把流收尾 ✓。
        await _closeFile();
        if (!resultStream.isClosed) {
          await resultStream.close();
        }
        return;
      }
      Log.error("Download", "Download failed: $e", s);
      await _setError(resultStream, e, s);
    } finally {
      timer?.cancel();
    }
  }

  Future<void> _scheduleDownload() async {
    var tasks = <Future>[];
    Object? firstError;
    StackTrace? firstStack;
    while (true) {
      // 取消 / 已有永久失败 ⇒ 不再派发新块 ✓；但仍要等**已在途**的块收尾 ✓，
      // 否则 `_download` 会先关掉文件 / 流，后台块再去写就会抛二次异常 ✗。
      if (_canceled || firstError != null) break;
      if (tasks.length >= maxConcurrent) {
        await Future.any(tasks);
      }
      final block = _blocks.firstWhereOrNull(
        (element) =>
            !element.downloading &&
            element.end - element.start > element.downloadedBytes,
      );
      if (block == null) {
        break;
      }
      block.downloading = true;
      var task = _fetchBlock(block);
      // ⭐ 派生 future 只负责"完成后从在途列表移除 + 记录首个错误" ✓ ——
      // 原实现在 onError 里 rethrow ✗：那个 future 没人监听 ⇒ 取消 / 失败时
      // 会额外冒出"Unhandled exception"✗；真正的错误由下面的 `Future.any` /
      // `Future.wait`（原 task 本身）统一抛出 ✓，不会丢 ✓。
      task.then<void>(
        (_) {
          tasks.remove(task);
        },
        onError: (Object e, StackTrace s) {
          firstError ??= e;
          firstStack ??= s;
          tasks.remove(task);
        },
      );
      tasks.add(task);
    }
    await Future.wait(tasks);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
  }

  /// 把缓冲区写到块内**当前偏移** ✓（调用方保证此刻 `_isWriting == false` ✓）。
  Future<void> _writeBuffer(_DownloadBlock block, List<int> buffer) async {
    if (buffer.isEmpty) return;
    _isWriting = true;
    try {
      await _file!.setPosition(block.start + block.downloadedBytes);
      await _file!.writeFrom(buffer);
      block.downloadedBytes += buffer.length;
      // 写入成功后才计入进度 ✓：失败时不能把"没落盘"的字节算成已完成 ✗。
      _currentBytes += buffer.length;
      buffer.clear();
      // 每次落盘都刷新断点状态 ✓：异常 / 断电后最多重下最后一段 ✓。
      await _writeStatus();
    } finally {
      _isWriting = false;
    }
  }

  /// 为单个请求派生取消令牌 ✓（dio 一个请求只接受一个 CancelToken）——
  /// 全局 `stop()` / 失败收尾会转发取消 ✓；单个响应不合法时只取消这一条连接 ✓，
  /// 不影响其他正在下载的块 ✓。
  CancelToken _newRequestToken() {
    final token = CancelToken();
    // 已经取消过了 ⇒ 直接取消子令牌 ✓（`whenCancel.then` 要等一个微任务才跑 ✓，
    // 这里先把状态同步过来，避免新请求在间隙里发出去 ✗）。
    if (_cancelToken.isCancelled) {
      token.cancel("download stopped");
      return token;
    }
    _cancelToken.whenCancel.then((_) {
      if (!token.isCancelled) {
        token.cancel("download stopped");
      }
    });
    return token;
  }

  /// 单块请求 + 响应校验 + 写入 ✓（不含重试，重试在 [_fetchBlock] ✓）。
  Future<void> _fetchBlockOnce(_DownloadBlock block) async {
    final start = block.start;
    final end = block.end;
    final rangeStart = start + block.downloadedBytes;
    final rangeEnd = end - 1;

    if (rangeStart > rangeEnd) {
      return;
    }

    var options = Options(
      responseType: ResponseType.stream,
      headers: {
        "Range": "bytes=$rangeStart-$rangeEnd",
        "Accept": "*/*",
        "Accept-Encoding": "deflate, gzip",
      },
      preserveHeaderCase: true,
    );
    final requestToken = _newRequestToken();
    var res = await _dio.get<ResponseBody>(
      url,
      options: options,
      cancelToken: requestToken,
    );
    if (_canceled) return;
    if (res.data == null) {
      throw Exception("Failed to block $start-$end");
    }
    try {
      // ⭐ 修复（2026-10-24）：服务器忽略 Range 时回 **200 + 整个文件** ✗ ——
      // 原先不校验状态码 / Content-Range ⇒ 整段数据被写到"块起点"，
      // 文件被撑大、块进度也超过块长度，最后竟按 `_currentBytes >= _fileSize` 判完成 ✗。
      // 现在要求 206 且 Content-Range 的起点 / 终点 / 总长完全一致 ✓，
      // 不符就整块按失败重试（有上限）✓。
      _checkPartialResponse(res, rangeStart, rangeEnd);
    } catch (_) {
      // 不消费 body 就不能直接丢 ✓ —— 取消这条请求以关闭连接、释放 socket ✓
      //（`ResponseBody.close` 是 dio 的 @internal API，不能直接用 ✗）。
      if (!requestToken.isCancelled) {
        requestToken.cancel("invalid partial response");
      }
      rethrow;
    }

    final expectedBytes = rangeEnd - rangeStart + 1;
    var receivedBytes = 0;
    var buffer = <int>[];
    await for (var data in res.data!.stream) {
      if (_canceled) return;
      receivedBytes += data.length;
      // 防御 ✓：body 不得超过 Content-Range 声明的长度 —— 否则会写到下一个块 ✗。
      if (receivedBytes > expectedBytes) {
        throw _RangeMismatchException(
          "Response body exceeds Content-Range "
          "(expected $expectedBytes bytes at $rangeStart-$rangeEnd)",
        );
      }
      buffer.addAll(data);
      if (buffer.length > 16 * 1024) {
        // ⭐ 2026-10-24：取消后不要再碰已关闭的文件句柄 ✓（否则会误报下载失败并清掉断点 ✗）。
        if (_isWriting || _canceled) continue;
        await _writeBuffer(block, buffer);
      }
    }

    if (buffer.isNotEmpty) {
      while (_isWriting) {
        if (_canceled) return;
        await Future.delayed(const Duration(milliseconds: 10));
      }
      if (_canceled) return;
      await _writeBuffer(block, buffer);
    }

    if (receivedBytes != expectedBytes) {
      // 服务端提前断流 ✓：块没写满，绝不能当作"这块已完成" ✗ ——
      // 否则调度器会反复挑到它、进度却不再前进 ✓ ⇒ 按失败重试 ✓。
      throw _RangeMismatchException(
        "Incomplete block body (expected $expectedBytes bytes "
        "at $rangeStart-$rangeEnd, got $receivedBytes)",
      );
    }
  }

  /// 分块下载（带**有限**重试）✓。
  ///
  /// ⭐ 修复（2026-10-24）：Range 不生效（回 200 / Content-Range 不符 / body 断流）
  /// 时网络层自己不会报错 ✗ ⇒ 必须自己判失败并重试；重试有上限，超限后交给上层收尾 ✓。
  Future<void> _fetchBlock(_DownloadBlock block) async {
    try {
      for (var attempt = 0; ; attempt++) {
        if (_canceled) return;
        try {
          await _fetchBlockOnce(block);
          return;
        } on _RangeMismatchException catch (e) {
          if (attempt >= _maxBlockRetry) {
            rethrow;
          }
          Log.warning(
            "Download",
            "Block ${block.start}-${block.end} "
                "attempt ${attempt + 1} failed: $e, retrying",
          );
          // 简单线性退避 ✓：服务端持续回 200 时不要瞬间打满重试次数 ✓。
          await Future.delayed(Duration(microseconds: 200000 * (attempt + 1)));
        }
      }
    } finally {
      // 成功、失败、取消都必须让调度器知道这块不再"在途" ✓。
      block.downloading = false;
    }
  }

  /// 校验 206 与 `Content-Range` ✓。
  void _checkPartialResponse(
    Response<ResponseBody> res,
    int rangeStart,
    int rangeEnd,
  ) {
    if (res.statusCode != HttpStatus.partialContent) {
      throw _RangeMismatchException(
        "Expected 206 Partial Content, got ${res.statusCode} "
        "(the server may ignore the Range header)",
      );
    }
    // 用 `[]` 而不是 `value()` ✓：重复的 Content-Range 头会让 `value()` 直接抛异常 ✗，
    // 这里按"不合法响应"处理，才能走重试 ✓。
    final contentRanges = res.headers["content-range"];
    final contentRange = contentRanges?.length == 1
        ? contentRanges!.first
        : null;
    final match = contentRange == null
        ? null
        : _contentRangePattern.firstMatch(contentRange);
    if (match == null) {
      throw _RangeMismatchException(
        "Missing or malformed Content-Range: $contentRanges",
      );
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start != rangeStart || end != rangeEnd || total != _fileSize) {
      throw _RangeMismatchException(
        "Content-Range mismatch: requested bytes "
        "$rangeStart-$rangeEnd/$_fileSize, got $contentRange",
      );
    }
  }

  /// 中断下载，但**保留**断点状态 ✓（`pause()` → `resume()` 靠它续传 ✓）。
  ///
  /// ⭐ 修复（2026-10-24）：只置 `_canceled` 打不断在途的 HEAD / 分块 GET ✗ ——
  /// 请求会一直挂到网络超时，`pause()` 之后文件还可能被继续写 ✗。
  /// 现在用 CancelToken 真正取消，并立即关闭文件句柄 ✓。
  Future<void> stop() async {
    _canceled = true;
    _cancelInFlight("download stopped");
    await _closeFile();
  }

  /// 取消并**丢弃**断点（payload + status）✓ —— 与 [stop] 不同：不可续传 ✓。
  ///
  /// ⚠️ 当前 `ArchiveDownloadTask.cancel()` 仍调 [stop]（那属于调用方，本轮不改 ✓）；
  /// 取消路径要清磁盘残留时改调本方法即可 ✓。
  Future<void> cancel() async {
    await stop();
    await _clearStatus();
    await _clearPayload();
  }
}

/// 分块响应与请求不一致 ✓（可重试）—— 例如服务器忽略 Range 回 200、
/// Content-Range 起点 / 长度不符、body 提前断流 ✓。
class _RangeMismatchException implements Exception {
  final String message;

  const _RangeMismatchException(this.message);

  @override
  String toString() => "RangeMismatch: $message";
}

class DownloadingStatus {
  /// The current downloaded bytes
  final int downloadedBytes;

  /// The total bytes of the file
  final int totalBytes;

  /// Whether the download is finished
  final bool isFinished;

  /// The download speed in bytes per second
  final int bytesPerSecond;

  const DownloadingStatus(
    this.downloadedBytes,
    this.totalBytes,
    this.bytesPerSecond, [
    this.isFinished = false,
  ]);

  @override
  String toString() {
    return "Downloaded: $downloadedBytes/$totalBytes ${isFinished ? "Finished" : ""}";
  }
}

class _DownloadBlock {
  final int start;
  final int end;
  int downloadedBytes;
  bool downloading;

  _DownloadBlock(this.start, this.end, this.downloadedBytes, this.downloading);

  @override
  String toString() {
    return "$start-$end-$downloadedBytes";
  }

  _DownloadBlock.fromString(String str)
    : start = int.parse(str.split("-")[0]),
      end = int.parse(str.split("-")[1]),
      downloadedBytes = int.parse(str.split("-")[2]),
      downloading = false;
}
