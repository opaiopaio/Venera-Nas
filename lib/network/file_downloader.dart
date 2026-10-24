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

  final _dio = Dio();

  RandomAccessFile? _file;

  bool _isWriting = false;

  int _kChunkSize = 16 * 1024 * 1024;

  bool _canceled = false;

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
  /// 只要 url / 长度 / ETag / 块边界有任何一处不匹配（含旧版纯文本格式 ✓），
  /// 就视为**不可信**：清掉状态文件并返回 false ✓，让调用方从头下载 ✓。
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
      // ETag 是"远端文件是否同一份"的最强证据 ✓；两端都有值时**必须**一致 ✓。
      final statusEtag = decoded["etag"];
      if (statusEtag != null && _etag != null && statusEtag != _etag) {
        throw const FormatException("remote file changed (etag mismatch)");
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

    var res = await _dio.head(url);
    var length = res.headers["content-length"]?.first;
    _fileSize = length == null ? 0 : int.parse(length);
    _etag = res.headers["etag"]?.first;

    // ⭐ 修复（2026-10-24）：没有合法长度 ⇒ 既不能分块也不能判定完成 ✓。
    // 原实现 `_fileSize = 0` ⇒ `_currentBytes >= _fileSize` 立即成立 ⇒ **空文件被当成下载完成** ✗。
    if (_fileSize <= 0) {
      throw Exception("Missing or invalid Content-Length for $url");
    }

    final canResume = await _tryReadStatus();
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

  /// ⭐ 失败收尾（2026-10-24）：关闭文件句柄 + 丢弃不可信断点状态 ✓。
  ///
  /// 出错时磁盘上的进度可能只写了一半 ✓ ⇒ 绝不能留给下一次当作断点 ✗。
  Future<void> _setError(
    StreamController<DownloadingStatus> stream,
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    await _file?.close();
    _file = null;
    await _clearStatus();
    stream.addError(error, stackTrace);
    await stream.close();
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
        await _file?.close();
        _file = null;
        await resultStream.close();
        return;
      }

      // check if file is downloaded
      if (_currentBytes >= _fileSize) {
        await _file!.close();
        _file = null;
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
        await _file?.close();
        _file = null;
        await resultStream.close();
        return;
      }
      await _file!.close();
      _file = null;
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
        await _file?.close();
        _file = null;
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
    while (true) {
      if (_canceled) return;
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
      task.then(
        (value) => tasks.remove(task),
        onError: (e) {
          if (_canceled) return;
          throw e;
        },
      );
      tasks.add(task);
    }
    await Future.wait(tasks);
  }

  Future<void> _fetchBlock(_DownloadBlock block) async {
    final start = block.start;
    final end = block.end;

    if (start > _fileSize) {
      return;
    }

    var options = Options(
      responseType: ResponseType.stream,
      headers: {
        "Range": "bytes=${start + block.downloadedBytes}-${end - 1}",
        "Accept": "*/*",
        "Accept-Encoding": "deflate, gzip",
      },
      preserveHeaderCase: true,
    );
    var res = await _dio.get<ResponseBody>(url, options: options);
    if (_canceled) return;
    if (res.data == null) {
      throw Exception("Failed to block $start-$end");
    }

    var buffer = <int>[];
    await for (var data in res.data!.stream) {
      if (_canceled) return;
      buffer.addAll(data);
      if (buffer.length > 16 * 1024) {
        if (_isWriting) continue;
        // ⭐ 2026-10-24：取消后不要再碰已关闭的文件句柄 ✓（否则会误报下载失败并清掉断点 ✗）。
        if (_canceled) return;
        _currentBytes += buffer.length;
        _isWriting = true;
        try {
          await _file!.setPosition(start + block.downloadedBytes);
          await _file!.writeFrom(buffer);
          block.downloadedBytes += buffer.length;
          buffer.clear();
          await _writeStatus();
        } finally {
          _isWriting = false;
        }
      }
    }

    if (buffer.isNotEmpty) {
      while (_isWriting) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      if (_canceled) return;
      _isWriting = true;
      try {
        _currentBytes += buffer.length;
        await _file!.setPosition(start + block.downloadedBytes);
        await _file!.writeFrom(buffer);
        block.downloadedBytes += buffer.length;
        await _writeStatus();
      } finally {
        _isWriting = false;
      }
    }

    block.downloading = false;
  }

  Future<void> stop() async {
    _canceled = true;
    await _file?.close();
    _file = null;
  }
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
