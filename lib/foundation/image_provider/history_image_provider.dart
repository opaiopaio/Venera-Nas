import 'dart:async' show Future;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
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
      var localComic = LocalManager().find(history.id, history.type);
      if (localComic == null) {
        // Try finding by ComicType.smb — history may reference a network
        // source but the comic was imported as SMB local.
        localComic = LocalManager().find(history.id, ComicType.smb);
      }
      if (localComic != null) {
        if (localComic.comicType == ComicType.smb || localComic.baseDir.startsWith('smb://')) {
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

  Future<Uint8List> _loadSmbCover(LocalComic comic) async {
    // Check disk cache first (reuse same cache key strategy as LocalComicImageProvider)
    final cacheKey = 'smb_cover:${comic.id}';
    final cached = await CacheManager().findCache(cacheKey);
    if (cached != null) {
      
      final bytes = await cached.readAsBytes();
      return Uint8List.fromList(bytes);
    }

    final baseDir = comic.baseDir;
    final coverName = comic.cover;
    final coverUrl = '${baseDir.endsWith('/') ? baseDir : '$baseDir/'}$coverName';
    final config = _parseSmbConfig(baseDir);
    final remotePath = _smbCoverPathFromUrl(config, coverUrl);
    final client = SmbClient(config: config);
    try {
      await client.connect();
      final data = await client.readFile(remotePath);
      final compressed = await LocalComicImageProvider.compressCoverImage(data);
      await CacheManager().writeCache(cacheKey, compressed);
      return Uint8List.fromList(compressed);
    } finally {
      await client.disconnect();
    }
  }

  static SmbConfig _parseSmbConfig(String url) {
    final uri = Uri.parse(url);
    final parts = uri.pathSegments;
    final share = parts.isNotEmpty ? parts.first : '';
    final userInfo = uri.userInfo.split(':');
    return SmbConfig(
      host: uri.host,
      port: uri.hasPort ? uri.port : 445,
      share: share,
      username: userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : '',
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : '',
    );
  }

  static String _smbCoverPathFromUrl(SmbConfig config, String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.length <= 1) return '';
    return segments.sublist(1).join('/');
  }

  @override
  Future<HistoryImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "history${history.id}${history.type.value}";
}
