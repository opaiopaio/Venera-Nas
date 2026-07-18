import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'local_comic_image.dart' as image_provider;

/// Simple semaphore to limit concurrent async operations.
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

class LocalComicImageProvider
    extends BaseImageProvider<image_provider.LocalComicImageProvider> {
  /// Image provider for normal image.
  ///
  /// [url] is the url of the image. Local file path is also supported.
  const LocalComicImageProvider(this.comic);

  final LocalComic comic;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    // SMB: read cover from remote share
    if (comic.comicType == ComicType.smb || comic.baseDir.startsWith('smb://')) {
      return _loadSmbCover();
    }

    File? file = comic.coverFile;
    if (!await file.exists()) {
      file = null;
      var dir = Directory(comic.directory);
      if (!await dir.exists()) {
        throw "Error: Comic not found.";
      }
      Directory? firstDir;
      await for (var entity in dir.list()) {
        if (entity is File) {
          if (_imageExtensions.contains(entity.extension)) {
            file = entity;
            break;
          }
        } else if (entity is Directory) {
          firstDir ??= entity;
        }
      }
      if (file == null && firstDir != null) {
        await for (var entity in firstDir.list()) {
          if (entity is File) {
            if (_imageExtensions.contains(entity.extension)) {
              file = entity;
              break;
            }
          }
        }
      }
    }
    if (file == null) {
      throw "Error: Cover not found.";
    }
    checkStop();
    var data = await file.readAsBytes();
    if (data.isEmpty) {
      throw "Exception: Empty file(${file.path}).";
    }
    return data;
  }

  static final _smbSemaphore = _Semaphore(2);

  Future<Uint8List> _loadSmbCover() async {
    // Check disk cache first
    final cacheKey = 'smb_cover:${comic.id}';
    final cached = await CacheManager().findCache(cacheKey);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      return Uint8List.fromList(bytes);
    }

    final baseDir = comic.baseDir;
    final coverName = comic.cover;

    // Build the full smb:// URL for the cover image.
    // If the cover is already a full URL (starts with smb://), use it directly.
    final String coverUrl;
    if (coverName.startsWith('smb://')) {
      coverUrl = coverName;
    } else {
      // baseDir is smb://host/share/path, cover is "cover.jpg" or similar
      coverUrl = '${baseDir.endsWith('/') ? baseDir : '$baseDir/'}$coverName';
    }

    final config = parseSmbConfigFromUrl(baseDir);
    final remoteCoverPath = smbPathFromUrl(coverUrl);

    final client = SmbClient(config: config);
    await _smbSemaphore.acquire();
    try {
      await client.connect();
      try {
        final data = await client.readFile(remoteCoverPath);
        if (data.isEmpty) {
          throw "Exception: Empty cover file on SMB.";
        }
        final compressed = await compressCoverImage(data);
        await CacheManager().writeCache(cacheKey, compressed);
        return Uint8List.fromList(compressed);
      } on Smb2Exception catch (e) {
        if (e.type != Smb2ErrorType.fileNotFound) rethrow;
        // Cover not found at expected path — search the directory.
        final smbDir = smbPathFromUrl(baseDir);
        final entries = await client.listDirectory(smbDir);
        // Try cover.* first, then any image
        const exts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];
        SmbEntry? found;
        for (final e in entries) {
          if (!e.isFile || !exts.contains(e.extension.toLowerCase())) continue;
          if (e.name.toLowerCase().startsWith('cover')) {
            found = e;
            break;
          }
          found ??= e;
        }
        // If not found in base directory, try first subdirectory (chapter)
        if (found == null) {
          for (final e in entries) {
            if (!e.isDirectory) continue;
            final subEntries = await client.listDirectory(e.path);
            for (final se in subEntries) {
              if (!se.isFile || !exts.contains(se.extension.toLowerCase())) continue;
              found = se;
              break;
            }
            if (found != null) break;
          }
        }
        if (found == null) rethrow;
        final data = await client.readFile(found.path);
        final compressed = await compressCoverImage(data);
        await CacheManager().writeCache(cacheKey, compressed);
        return Uint8List.fromList(compressed);
      }
    } finally {
      await client.disconnect();
      _smbSemaphore.release();
    }
  }

  /// Compress cover image for cache storage.
  /// Resize to max 512px and encode as JPEG quality 85.
  /// Runs on a background isolate to avoid blocking the UI thread.
  static const _imageExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe',
  ];

  static Future<List<int>> compressCoverImage(Uint8List bytes) {
    return Isolate.run(() {
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return bytes.toList();

        // Resize to max 512px width, keeping aspect ratio via auto-computed height.
        final maxSide = 512;
        if (decoded.width > maxSide || decoded.height > maxSide) {
          final resized = img.copyResize(decoded, width: maxSide);
          return img.encodeJpg(resized, quality: 85);
        }
        return img.encodeJpg(decoded, quality: 85);
      } catch (_) {
        return bytes.toList();
      }
    });
  }

  @override
  Future<LocalComicImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "local${comic.id}${comic.comicType.value}";
}
