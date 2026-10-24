import 'dart:async' show Future;
import 'dart:convert' show utf8;
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

  /// ⭐ 修复（2026-10-24）：磁盘文件名由**完整键**派生 ✓ —— 不再用 32 位 `hashCode` ✗：
  /// 后者跨版本/跨平台不稳定且容易碰撞 ⇒ 两张封面会指向同一个文件（串味 ✓）、
  /// 删除时又会误删别人的封面 ✗。
  /// 这里用 FNV-1a（63 位）+ 键长度后缀：稳定、可复现，并进一步区分等长不同键 ✓。
  static String _fileNameFor(String key) {
    var hash = 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF;
    for (final unit in utf8.encode(key)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    final hex = hash.toRadixString(16).padLeft(15, '0');
    return '${hex}_${key.length.toRadixString(16)}.cover';
  }

  static void _deleteFile(String name) {
    var file = File(FilePath.join(App.dataPath, 'favorite_cover', name));
    if (file.existsSync()) {
      file.delete();
    }
  }

  static void delete(String id, int intKey) {
    // 新派生 ✓
    _deleteFile(_fileNameFor('$id@$intKey'));
    // 兼容旧版本残留（旧键 = `id + intKey`，文件名 = 其 hashCode ✓）
    _deleteFile((id + intKey.toString()).hashCode.toString());
  }

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    var sourceKey = ComicSource.fromIntKey(intKey)?.key;
    var file = File(
      FilePath.join(App.dataPath, 'favorite_cover', _fileNameFor(key)),
    );
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

  /// ⭐ 修复（2026-10-24）：键必须带分隔符 ✓ —— 原 `id + intKey` 会把
  /// (`"12"`, 3) 与 (`"1"`, 23) 撞成同一个键 ⇒ 封面串味 / 误删 ✗。
  @override
  String get key => '$id@$intKey';

  /// 修复（2026-10-09）：load() 走的是 `ImageDownloader.loadThumbnail(url, sourceKey)`，
  /// 其磁盘缓存键为 `"$url@$sourceKey"`（见 network/images.dart），与本类 `key` 不同 ⇒ 原清理命不中。
  @override
  String get cacheKey => "$url@${ComicSource.fromIntKey(intKey)?.key}";
}
