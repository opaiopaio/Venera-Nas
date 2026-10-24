import 'dart:io';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'smb_config.dart';
import 'smb_serial.dart';

/// High-level client for interacting with an SMB share.
///
/// Wraps [Smb2Pool] from the `dart_smb2` package, providing convenience
/// methods for listing directories and reading files that fit naturally
/// into Venera's local-comic pipeline.
///
/// ⭐ 2026-10-24：**所有原生调用都经过 [SmbSerial]** ✓ —— libsmb2 在并发使用 /
/// 读到一半被 disconnect 时会原生崩溃（`0xc0000005` ✓，事件日志实证 ✓）。
/// 闸门放在这一层 ✓ ⇒ 阅读器、封面、切章列目录、下载器、导入器**共用同一把锁** ✓。
///
/// Usage:
/// ```dart
/// final client = SmbClient(config: myConfig);
/// await client.connect();
/// final entries = await client.listDirectory('Comics/Series');
/// final bytes = await client.readFile('Comics/Series/Chapter1/001.jpg');
/// await client.disconnect();
/// ```
class SmbClient {
  final SmbConfig config;

  Smb2Pool? _pool;

  SmbClient({required this.config});

  /// ⭐ 2026-10-25：**共享客户端池** ✓ —— 供"短操作"复用连接 ✓。
  ///
  /// 为什么需要（实测日志 ✓）：历史页封面是 `ImageProvider` ✓，**每个封面**都 `new SmbClient()` ✗
  /// ⇒ 每次 `Smb2Pool.connect(workers: 4)` = **4 条连接** ✗；25 个封面 + 图片层失败重试
  /// ⇒ **连接被刷爆** ✗ ⇒ 路由器 SMB 侧资源/带宽占满 ✓ ⇒ 扫描/读图全部排队超时 ✗
  ///（日志现象：`Socket connect failed with 10060` ✓）
  ///
  /// 现在：按 主机+共享 缓存一个客户端 ✓ ⇒ 封面 / 历史 / 导入 / 切章列表**共用**连接 ✓，
  /// 只保留一条会话 ✓（阅读器另有自己的复用逻辑 ✓）。
  static final Map<String, SmbClient> _sharedClients = {};

  static String _keyOf(SmbConfig config) =>
      '${config.host}|${config.port}|${config.share}|'
      '${config.username}|${config.password.hashCode}|${config.domain}';

  /// 取得（必要时创建）**共享**客户端 ✓ —— ⚠️ 调用方**不要** `disconnect()` ✗
  ///（共享连接被断开会影响其它调用方 ✓；需要断开时用 [closeAllShared] ✓）。
  static SmbClient shared(SmbConfig config) {
    return _sharedClients.putIfAbsent(
      _keyOf(config),
      () => SmbClient(config: config),
    );
  }

  /// 断开并清空所有共享客户端 ✓（阅读器"重置 SMB 连接" / 退出时用 ✓）。
  static Future<void> closeAllShared() async {
    final list = _sharedClients.values.toList();
    _sharedClients.clear();
    for (final client in list) {
      try {
        await client.disconnect();
      } catch (_) {
        // 单条失败不影响其它 ✓。
      }
    }
  }

  /// Whether the client is currently connected.
  ///
  /// ⚠️ 只表示"池对象非空" ✓（复查记录 ✓）—— 连接可能已被服务器断开 ✓；
  /// 真正的失败会在下一次原生调用上暴露 ✓。
  bool get isConnected => _pool != null;

  /// Connect to the SMB share.
  ///
  /// [high] = true 表示"用户在等" ✓（阅读器当前页 ✓）；后台任务用 false ✓。
  Future<void> connect({bool high = false}) async {
    // ⚠️ 2026-10-24：底层库（`dart_smb2` → libsmb2）**没有端口参数** ✗ ⇒ 非 445 端口
    // 原来会**静默连到 445** ✗（用户只看到"连不上"、查不出原因 ✓）⇒ 这里改为**明确报错** ✓。
    if (config.port != 445) {
      throw "SMB 端口 ${config.port} 暂不支持：当前底层库仅支持 445 端口，"
          "请在 NAS/路由器上使用标准 SMB 端口（445）。";
    }
    await SmbSerial.run(() async {
      // ⭐ 2026-10-25：**已连接就直接复用** ✓ —— 共享客户端会被频繁 `connect()`
      //（每个封面/每次列目录 ✓）；若每次都重连 ✗ ⇒ 又会刷连接 ✗（正是要修的问题 ✓）。
      if (_pool != null) return;
      _pool = await Smb2Pool.connect(
        host: config.host,
        share: config.share,
        user: config.username,
        password: config.password,
        domain: config.domain,
        timeoutSeconds: 30,
        workers: 4,
        // ⭐ 2026-10-24：协议选项透传 ✓（服务器"强制签名/加密"或需指定方言时用得上 ✓）。
        signing: config.signing,
        seal: config.seal,
        version: config.version,
      );
    }, high: high);
  }

  /// Disconnect from the SMB share and release resources.
  Future<void> disconnect() async {
    final pool = _pool;
    if (pool == null) return;
    _pool = null;
    await SmbSerial.run(() async {
      await pool.disconnect();
    });
  }

  Smb2Pool get _p {
    final pool = _pool;
    if (pool == null) {
      throw StateError('SmbClient is not connected. Call connect() first.');
    }
    return pool;
  }

  /// List the contents of a directory on the SMB share.
  ///
  /// [path] is relative to the share root (e.g. `'Comics'` or `''`).
  /// Returns a list of [SmbEntry] objects with name, path, type and size.
  Future<List<SmbEntry>> listDirectory(String path, {bool high = false}) async {
    final entries = await SmbSerial.run(
      () => _p.listDirectory(path),
      high: high,
    );
    return entries.map((e) {
      final entryPath = path.isEmpty ? e.name : '$path/${e.name}';
      return SmbEntry(
        name: e.name,
        path: entryPath,
        isDirectory: e.isDirectory,
        size: e.size,
        modified: e.stat.modified,
      );
    }).toList();
  }

  /// Check whether a path exists on the SMB share.
  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } on Smb2Exception catch (e) {
      if (e.type == Smb2ErrorType.fileNotFound) {
        return false;
      }
      rethrow;
    }
  }

  /// Read the entire contents of a file on the SMB share into memory.
  ///
  /// ⭐ [high] = true 表示"用户在等"（阅读器当前页 ✓）—— 会优先于后台预取 ✓。
  Future<Uint8List> readFile(String path, {bool high = false}) async {
    return SmbSerial.run(() => _p.readFile(path), high: high);
  }

  /// Read a byte range from a file on the SMB share.
  ///
  /// [offset] is 0-based. [length] is the maximum number of bytes to read.
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
    bool high = false,
  }) async {
    return SmbSerial.run(
      () => _p.readFileRange(path, offset: offset, length: length),
      high: high,
    );
  }

  /// Get file metadata without reading its contents.
  Future<Smb2Stat> stat(String path, {bool high = false}) async {
    return SmbSerial.run(() => _p.stat(path), high: high);
  }

  /// Stream a file from the SMB share in chunks.
  ///
  /// This is the preferred way to read large files (e.g. CBZ archives)
  /// without loading them entirely into memory.
  ///
  /// ⚠️ 流式读**不经过全局闸门** ✓ —— 它横跨多次原生调用 ✓，若整段持锁会把其它操作
  /// 卡住任意长时间 ✗。⚠️ 当前项目**未使用**本方法 ✓（属预留 API ✓），
  /// 若将来启用，调用方需自行保证不与其它 SMB 操作并发 ✓。
  Stream<Uint8List> streamFile(
    String path, {
    int chunkSize = 1024 * 1024,
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) {
    return _p.streamFile(
      path,
      chunkSize: chunkSize,
      onProgress: onProgress,
      isCanceled: isCanceled,
    );
  }

  /// Download a file from the SMB share to a local file path.
  Future<void> downloadToFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    final localFile = File(localPath);
    await SmbSerial.run(
      () => _p.downloadToFile(
        remotePath,
        localFile,
        onProgress: onProgress,
        isCanceled: isCanceled,
      ),
    );
  }

  /// Write data to a file on the SMB share.
  ///
  /// Creates or overwrites the file at [remotePath] with [data].
  /// [onProgress] is called with (bytesSent, totalBytes) during the upload.
  Future<void> writeFile(
    String remotePath,
    Uint8List data, {
    void Function(int sent, int total)? onProgress,
  }) async {
    await SmbSerial.run(() => _p.writeFile(remotePath, data));
    onProgress?.call(data.length, data.length);
  }

  /// Write data from a stream to a file on the SMB share.
  ///
  /// ⚠️ 与 [streamFile] 同理：**不经过全局闸门** ✓（横跨多次原生调用 ✓），
  /// 当前项目未使用 ✓，启用时需调用方自行保证不并发 ✓。
  Future<void> streamWrite(String remotePath, Stream<Uint8List> stream) async {
    await _p.streamWrite(remotePath, stream);
  }

  /// Recursively create directories on the SMB share.
  ///
  /// [remotePath] is a share-relative path (e.g. `'Comics/Series/Chapter1'`).
  /// Intermediate directories that already exist are silently skipped.
  Future<void> mkdirs(String remotePath) async {
    if (remotePath.isEmpty) return;
    final parts = remotePath.replaceAll('\\', '/').split('/');
    var current = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      current = current.isEmpty ? part : '$current/$part';
      try {
        await SmbSerial.run(() => _p.mkdir(current));
      } on Smb2Exception catch (e) {
        // Silently ignore already-exists errors
        if (e.type != Smb2ErrorType.alreadyExists) {
          rethrow;
        }
      }
    }
  }

  /// Reconnect the client (e.g. after a network interruption).
  Future<void> reconnect({bool high = false}) async {
    await disconnect();
    await connect(high: high);
  }
}
