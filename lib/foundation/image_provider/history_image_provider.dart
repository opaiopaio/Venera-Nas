import 'dart:async' show Future;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';
import '../history.dart';
import 'base_image_provider.dart';
import 'history_image_provider.dart' as image_provider;
import 'local_comic_image.dart';

class HistoryImageProvider
    extends BaseImageProvider<image_provider.HistoryImageProvider> {
  /// Image provider for normal image.
  ///
  /// [url] is the url of the image. Local file path is also supported.
  const HistoryImageProvider(this.history);

  final History history;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    var url = history.cover;
    if (!url.contains('/')) {
      // Try finding by ComicType.smb — history may reference a network
      // source but the comic was imported as SMB local.
      final localComic =
          LocalManager().find(history.id, history.type) ??
          LocalManager().find(history.id, ComicType.smb);
      if (localComic != null) {
        if (localComic.comicType == ComicType.smb ||
            localComic.baseDir.startsWith('smb://')) {
          return _loadSmbCover(localComic);
        }
        return localComic.coverFile.readAsBytes();
      }
      var comicSource =
          history.type.comicSource ?? (throw "Comic source not found.");
      var comic = await comicSource.loadComicInfo!(history.id);
      checkStop();
      url = comic.data.cover;
      history.cover = url;
      HistoryManager().addHistory(history);
    }
    await for (var progress in ImageDownloader.loadThumbnail(
      url,
      history.type.sourceKey,
      history.id,
    )) {
      checkStop();
      chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.totalBytes,
        ),
      );
      if (progress.imageBytes != null) {
        return progress.imageBytes!;
      }
    }
    throw "Error: Empty response body.";
  }

  /// ⭐ 2026-10-25：**已知缺失封面**缓存 ✓ —— 坏盘/被删的漫画会反复加载失败 ✓，
  /// 每次重试都占用 SMB 连接与全局闸门 ✗ ⇒ 扫描/读图排队超时 ✓（实测日志 ✓）。
  static final Set<String> _failedSmbCovers = {};

  /// ⭐ 2026-10-25：封面加载**限并发 2** ✓ —— 历史有几十条时别一拥而上抢 SMB 闸门 ✗
  ///（阅读器读图是高优先级 ✓，封面是次要的 ✓）。
  static final _smbSemaphore = Semaphore(2);

  Future<Uint8List> _loadSmbCover(LocalComic comic) async {
    // Check disk cache first (reuse same cache key strategy as LocalComicImageProvider)
    final cacheKey = 'smb_cover:${comic.id}';
    if (_failedSmbCovers.contains(cacheKey)) {
      throw "Invalid Status Code: 404 (SMB cover missing, cached failure)";
    }
    final cached = await CacheManager().findCache(cacheKey);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      return Uint8List.fromList(bytes);
    }

    final baseDir = comic.baseDir;
    final coverName = comic.cover;

    final String coverUrl;
    if (coverName.startsWith('smb://')) {
      coverUrl = coverName;
    } else {
      coverUrl = '${baseDir.endsWith('/') ? baseDir : '$baseDir/'}$coverName';
    }

    final config = parseSmbConfigFromUrl(baseDir);
    final remoteCoverPath = smbPathFromUrl(coverUrl);

    final client = SmbClient.shared(config);
    await _smbSemaphore.acquire();
    try {
      await client.connect();
      try {
        final data = await client.readFile(remoteCoverPath);
        if (data.isEmpty) {
          throw "Exception: Empty cover file on SMB.";
        }
        final compressed = await LocalComicImageProvider.compressCoverImage(
          data,
        );
        await CacheManager().writeCache(cacheKey, compressed);
        return Uint8List.fromList(compressed);
      } on Smb2Exception catch (e) {
        if (e.type != Smb2ErrorType.fileNotFound) rethrow;
        // Cover not found at expected path — search the directory.
        final smbDir = smbPathFromUrl(baseDir);
        final List<SmbEntry> entries;
        try {
          entries = await client.listDirectory(smbDir);
        } on Smb2Exception catch (e) {
          if (e.type == Smb2ErrorType.fileNotFound) _failSmbCover(cacheKey);
          rethrow;
        }
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
              if (!se.isFile || !exts.contains(se.extension.toLowerCase())) {
                continue;
              }
              found = se;
              break;
            }
            if (found != null) break;
          }
        }
        if (found == null) _failSmbCover(cacheKey);
        final data = await client.readFile(found.path);
        final compressed = await LocalComicImageProvider.compressCoverImage(
          data,
        );
        await CacheManager().writeCache(cacheKey, compressed);
        return Uint8List.fromList(compressed);
      }
    } finally {
      // ⭐ 共享客户端：**不在此断开** ✓（统一由 SmbClient.closeAllShared / 重置入口管理 ✓）。
      _smbSemaphore.release();
    }
  }

  /// ⭐ 2026-10-25：封面**确定缺失** ⇒ 记住并抛"404" ✓（上层不再重试 ✓）。
  static Never _failSmbCover(String cacheKey) {
    _failedSmbCovers.add(cacheKey);
    throw "Invalid Status Code: 404 (SMB cover missing)";
  }

  @override
  Future<HistoryImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "history${history.id}${history.type.value}";

  /// 修复（2026-10-09）：SMB 封面磁盘缓存键为 `smb_cover:<localComic.id>`（见 _loadSmbCover），
  /// 而该 localComic 是用 `LocalManager().find(history.id, …)` 查到的 ⇒ 键中的 id 即 `history.id`。
  /// 网络缩略图路径（cover 含 '/'）保持原行为不变，避免误删无关缓存。
  @override
  String get cacheKey =>
      history.cover.contains('/') ? key : 'smb_cover:${history.id}';
}
