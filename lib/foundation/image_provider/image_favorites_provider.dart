import 'dart:async' show Future, StreamController;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/image_cache_keys.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';
import 'package:venera_nas/utils/io.dart';
import '../history.dart';
import 'base_image_provider.dart';
import 'image_favorites_provider.dart' as image_provider;

class ImageFavoritesProvider
    extends BaseImageProvider<image_provider.ImageFavoritesProvider> {
  /// Image provider for imageFavorites
  const ImageFavoritesProvider(this.imageFavorite);

  final ImageFavorite imageFavorite;

  int get page => imageFavorite.page;

  String get sourceKey => imageFavorite.sourceKey;

  String get cid => imageFavorite.id;

  String get eid => imageFavorite.eid;

  @override
  Future<Uint8List> load(
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    // ⭐ 2026-10-26：SMB 收藏**不能**走网络分支 ✓ ——
    // ① 页缓存键对不上：阅读器侧 SMB 没有 `ComicSource`（`sourceKey == null` ✓），
    //    落盘键是 `…@null@…` ✓；而收藏条目里存的是 `'smb'` ✗ ⇒ 原实现永远 miss ✓；
    // ② `ImageDownloader.loadComicImage` 依赖 `ComicSource.find(sourceKey)` ✓，
    //    `'smb'` 查不到（原先走强解包直接崩 ✗）⇒ 未命中时必然失败 ✓。
    // 因此 SMB 单独走「页缓存 → LocalManager 补页地址 → SmbClient 读 → 落盘」✓；
    // **非 SMB 源保持原逻辑不变** ✓。
    if (isSmbSource) {
      return _loadSmbImage(checkStop);
    }
    var imageKey = imageFavorite.imageKey;
    var localImage = await getImageFromLocal();
    checkStop?.call();
    if (localImage != null) {
      return localImage;
    }
    var cacheImage = await readFromCache();
    checkStop?.call();
    if (cacheImage != null) {
      return cacheImage;
    }
    var gotImageKey = false;
    if (imageKey == "") {
      imageKey = await getImageKey();
      checkStop?.call();
      gotImageKey = true;
    }
    Uint8List image;
    try {
      image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
    } catch (e) {
      if (gotImageKey) {
        rethrow;
      } else {
        imageKey = await getImageKey();
        image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
      }
    }
    await writeToCache(image);
    return image;
  }

  /// 是否 SMB 收藏 ✓（`'smb'` 是内置类型键，不可能与网络源重名 ✓）。
  bool get isSmbSource => ComicType.fromKey(sourceKey) == ComicType.smb;

  /// 页缓存键里的 `sourceKey` 字段 ✓。
  ///
  /// SMB 在阅读器侧 `comicSource == null` ⇒ 真实落盘键是 `@null@` ✓；
  /// 收藏条目却存 `'smb'` ⇒ **必须归一为 null** 才能命中同一份页缓存 ✓。
  String? get pageCacheSourceKey => isSmbSource ? null : sourceKey;

  /// SMB 收藏的读图路径 ✓（不经过 ComicSource / HTTP ✓）。
  Future<Uint8List> _loadSmbImage(void Function()? checkStop) async {
    // 收藏页自身的快速缓存（md5(key)）✓ —— 与页缓存相互独立，先查 ✓。
    var imageKey = imageFavorite.imageKey;
    var cacheImage = await readFromCache();
    checkStop?.call();
    if (cacheImage != null) {
      return cacheImage;
    }
    // 旧数据 / 导入数据可能没有 imageKey ⇒ 用本地库列一遍该章页地址 ✓。
    if (imageKey.isEmpty) {
      imageKey = await _resolveSmbPageKey();
      // 同步回模型 ✓：解码失败时 `cacheKey` 才能指向真实页缓存文件 ✓。
      imageFavorite.imageKey = imageKey;
      checkStop?.call();
    }
    // 阅读器落盘用的键（`sourceKey` 归一为 null ✓）—— 命中就省一次 NAS 读取 ✓。
    final pageCacheKey = readerPageCacheKey(
      imageKey,
      pageCacheSourceKey,
      cid,
      eid,
    );
    final cached = await CacheManager().findCache(pageCacheKey);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      if (bytes.isNotEmpty) {
        final data = Uint8List.fromList(bytes);
        // 收藏页快速缓存写失败不影响本次显示 ✓（页缓存仍然命中 ✓）。
        try {
          await writeToCache(data);
        } catch (_) {}
        return data;
      }
    }
    checkStop?.call();
    final client = SmbClient.shared(parseSmbConfigFromUrl(imageKey));
    await client.connect();
    final bytes = await client.readFile(smbPathFromUrl(imageKey));
    if (bytes.isEmpty) {
      throw "Error: Empty response body.";
    }
    checkStop?.call();
    // ⭐ 落盘失败**不得**拖垮本次读图 ✓：字节已经拿到了，最多下次再读一次 NAS ✓。
    try {
      await CacheManager().writeCache(pageCacheKey, bytes);
      await writeToCache(bytes);
    } catch (_) {}
    return bytes;
  }

  /// 用本地库把「第 N 章第 P 页」解析成 `smb://…` 页地址 ✓。
  Future<String> _resolveSmbPageKey() async {
    // ⚠️ 必须用 **收藏的漫画 id** 查本地库（原 `getImageFromLocal` 误把 sourceKey 当 id ✗），
    // 并且 SMB 页在本地库里没有对应文件 ⇒ 只能列远程目录 ✓。
    final localComic = LocalManager().find(cid, ComicType.smb);
    if (localComic == null) {
      throw "Error: SMB comic not found for this image favorite.";
    }
    // `ep` 是 1 基的章节序号；旧数据缺失时按第 1 章处理 ✓。
    final ep = imageFavorite.ep > 0 ? imageFavorite.ep : 1;
    final images = await LocalManager().getImages(cid, ComicType.smb, ep);
    final index = page - 1;
    if (index < 0 || index >= images.length) {
      throw "Error: Image favorite page $page is out of range "
          "(${images.length} pages).";
    }
    return images[index];
  }

  Future<void> writeToCache(Uint8List image) async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    await file.writeAsBytes(image);
  }

  Future<Uint8List?> readFromCache() async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      return null;
    }
    return await file.readAsBytes();
  }

  /// Delete a image favorite cache
  static Future<void> deleteFromCache(ImageFavorite imageFavorite) async {
    var fileName = md5.convert(imageFavorite.imageKey.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<Uint8List?> getImageFromLocal() async {
    var localComic = LocalManager().find(
      sourceKey,
      ComicType.fromKey(sourceKey),
    );
    if (localComic == null) {
      return null;
    }
    var epIndex = localComic.chapters?.ids.toList().indexOf(eid) ?? -1;
    if (epIndex == -1 && localComic.hasChapters) {
      return null;
    }
    var images = await LocalManager().getImages(
      sourceKey,
      ComicType.fromKey(sourceKey),
      epIndex,
    );
    var data = await File(images[page]).readAsBytes();
    return data;
  }

  Future<Uint8List> getImageFromNetwork(
    String imageKey,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    await for (var progress in ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      cid,
      eid,
    )) {
      checkStop?.call();
      if (chunkEvents != null) {
        chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: progress.currentBytes,
            expectedTotalBytes: progress.totalBytes,
          ),
        );
      }
      if (progress.imageBytes != null) {
        return progress.imageBytes!;
      }
    }
    throw "Error: Empty response body.";
  }

  Future<String> getImageKey() async {
    String sourceKey = imageFavorite.sourceKey;
    String cid = imageFavorite.id;
    String eid = imageFavorite.eid;
    var page = imageFavorite.page;
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource == null) {
      throw "Error: Comic source not found.";
    }
    var res = await comicSource.loadComicPages!(cid, eid);
    return res.data[page - 1];
  }

  @override
  Future<ImageFavoritesProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key =>
      "ImageFavorites ${imageFavorite.imageKey}@${imageFavorite.sourceKey}@${imageFavorite.id}@${imageFavorite.eid}";

  /// 修复（2026-10-09）：加载走 `ImageDownloader.loadComicImage(imageKey, sourceKey, cid, eid)`，
  /// 其磁盘缓存键由 [readerPageCacheKey] 统一拼装（与本类 `key`（内存键）不同 ✓）。
  ///
  /// ⭐ 2026-10-26：改为调用统一函数 ✓ —— 原先行内拼接的格式与页缓存键**完全一致** ✓
  ///（`imageKey@sourceKey@cid@eid`），因此可安全替换、行为不变 ✓。
  /// ⭐ 2026-10-26（P1 ✓）：SMB 的 `sourceKey` 归一为 null ✓ —— 否则键里是 `@smb@`，
  /// 而阅读器落盘的是 `@null@` ⇒ 永远 miss、解码失败也删不到真实缓存 ✗。
  @override
  String get cacheKey =>
      readerPageCacheKey(imageFavorite.imageKey, pageCacheSourceKey, cid, eid);
}
