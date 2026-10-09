import 'dart:async' show Future;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'local_favorite_image.dart' as image_provider;

class LocalFavoriteImageProvider
    extends BaseImageProvider<image_provider.LocalFavoriteImageProvider> {
  /// Image provider for normal image.
  const LocalFavoriteImageProvider(this.url, this.id, this.intKey);

  final String url;

  final String id;

  final int intKey;

  static void delete(String id, int intKey) {
    var fileName = (id + intKey.toString()).hashCode.toString();
    var file = File(FilePath.join(App.dataPath, 'favorite_cover', fileName));
    if (file.existsSync()) {
      file.delete();
    }
  }

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    var sourceKey = ComicSource.fromIntKey(intKey)?.key;
    var fileName = key.hashCode.toString();
    var file = File(FilePath.join(App.dataPath, 'favorite_cover', fileName));
    if (await file.exists()) {
      return await file.readAsBytes();
    } else {
      await file.create(recursive: true);
    }
    checkStop();
    await for (var progress in ImageDownloader.loadThumbnail(url, sourceKey)) {
      checkStop();
      chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.totalBytes,
        ),
      );
      if (progress.imageBytes != null) {
        var data = progress.imageBytes!;
        await file.writeAsBytes(data);
        return data;
      }
    }
    throw "Error: Empty response body.";
  }

  @override
  Future<LocalFavoriteImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture(this);
  }

  @override
  String get key => id + intKey.toString();

  /// 修复（2026-10-09）：load() 走的是 `ImageDownloader.loadThumbnail(url, sourceKey)`，
  /// 其磁盘缓存键为 `"$url@$sourceKey"`（见 network/images.dart），与本类 `key` 不同 ⇒ 原清理命不中。
  @override
  String get cacheKey => "$url@${ComicSource.fromIntKey(intKey)?.key}";
}
