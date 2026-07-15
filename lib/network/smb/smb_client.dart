import 'dart:io';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'smb_config.dart';

/// High-level client for interacting with an SMB share.
///
/// Wraps [Smb2Pool] from the `dart_smb2` package, providing convenience
/// methods for listing directories and reading files that fit naturally
/// into Venera's local-comic pipeline.
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

  /// Whether the client is currently connected.
  bool get isConnected => _pool != null;

  /// Connect to the SMB share.
  Future<void> connect() async {
    if (_pool != null) {
      await _pool!.disconnect();
    }
    _pool = await Smb2Pool.connect(
      host: config.host,
      share: config.share,
      user: config.username,
      password: config.password,
      domain: config.domain,
      timeoutSeconds: 30,
      workers: 4,
    );
  }

  /// Disconnect from the SMB share and release resources.
  Future<void> disconnect() async {
    if (_pool != null) {
      await _pool!.disconnect();
      _pool = null;
    }
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
  Future<List<SmbEntry>> listDirectory(String path) async {
    final entries = await _p.listDirectory(path);
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
      await _p.stat(path);
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
  /// For large files, consider using [readFileRange] or [streamFile] instead.
  Future<Uint8List> readFile(String path) async {
    return _p.readFile(path);
  }

  /// Read a byte range from a file on the SMB share.
  ///
  /// [offset] is 0-based. [length] is the maximum number of bytes to read.
  Future<Uint8List> readFileRange(
    String path, {
    int offset = 0,
    required int length,
  }) async {
    return _p.readFileRange(path, offset: offset, length: length);
  }

  /// Get file metadata without reading its contents.
  Future<Smb2Stat> stat(String path) async {
    return _p.stat(path);
  }

  /// Stream a file from the SMB share in chunks.
  ///
  /// This is the preferred way to read large files (e.g. CBZ archives)
  /// without loading them entirely into memory.
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
    await _p.downloadToFile(
      remotePath,
      localFile,
      onProgress: onProgress,
      isCanceled: isCanceled,
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
    await _p.writeFile(remotePath, data);
    onProgress?.call(data.length, data.length);
  }

  /// Write data from a stream to a file on the SMB share.
  ///
  /// Useful for large files that should not be fully loaded into memory.
  Future<void> streamWrite(
    String remotePath,
    Stream<Uint8List> stream,
  ) async {
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
        await _p.mkdir(current);
      } on Smb2Exception catch (e) {
        // Silently ignore already-exists errors
        if (e.type != Smb2ErrorType.alreadyExists) {
          rethrow;
        }
      }
    }
  }

  /// Reconnect the client (e.g. after a network interruption).
  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }
}
