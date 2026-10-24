import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/foundation/appdata.dart';
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
///
/// ⭐ 2026-10-25：改名为公开 `Semaphore` ✓ —— 历史封面加载也要限并发 ✓
///（原先私有 `_Semaphore` 只在同文件可用 ✗）。
class Semaphore {
  Semaphore(this._maxCount);
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

/// SMB 封面加载的**共用**并发闸门与「已知缺失」缓存 ✓。
///
/// ⭐ 修复（2026-10-24）：原先 `LocalComicImageProvider` 与 `HistoryImageProvider`
/// **各持一套** `Semaphore(2)` 与失败集合 ✗ —— 同一张封面在两个入口下会各记一次、
/// 并发上限实际翻倍（4 ✓），坏盘封面也会被重复重试 ✓。
/// 现在统一走这里 ✓；清理入口见 [clearFailures] ✓。
class SmbCoverLoader {
  SmbCoverLoader._();

  /// SMB 封面并发 2（实测：并发再高会拖慢阅读器读图 ✓）。
  static final Semaphore semaphore = Semaphore(2);

  /// ⭐ 2026-10-25：失败记录改成「键 ⇒ 失败时间」✓ —— 旧实现是纯 `Set` ✗
  /// ⇒ 一次失败会**永久生效** ✗：用户改好 NAS 配置、插回硬盘、或服务器重启后，
  /// 封面仍然一直被判定为 404 且不再重试 ✓（只能重启 App ✗）。
  /// 现在超过 [failureTtl] 自动重试 ✓；配置变更 / 重置连接也会清空 ✓。
  static final Map<String, DateTime> _failedAt = {};

  /// 失败记录的有效期 ✓（10 分钟 ✓：既不让坏封面反复占用连接 ✓，
  /// 又不会让"刚修好的盘"长时间看不到封面 ✓）。
  static const Duration failureTtl = Duration(minutes: 10);

  /// 上次看到的 `smbServers` 列表对象 ✓ —— 换新（= 设置页保存 / 备份恢复 ✓）即视为
  /// **配置变更** ✓ ⇒ 清空失败记录，允许重新尝试 ✓。
  static Object? _serversSignature;

  /// ⭐ 2026-10-25（用户实测 ✓）：**封面缓存键必须带路径** ✗ ——
  /// 原来只有 comic.id ✓，而扫描出来的 SMB 漫画 **id 可能重复** ✗
  /// ⇒ 两本漫画共用同一个封面缓存 ⇒ 显示成同一张封面 ✗。
  static String cacheKey(String comicId, {String? baseDir}) =>
      (baseDir == null || baseDir.isEmpty)
      ? 'smb_cover:$comicId'
      : 'smb_cover:$baseDir|$comicId';

  static bool isFailed(String cacheKey) {
    _syncConfigChange();
    final failedAt = _failedAt[cacheKey];
    if (failedAt == null) return false;
    if (DateTime.now().difference(failedAt) >= failureTtl) {
      _failedAt.remove(cacheKey);
      return false;
    }
    return true;
  }

  static void markFailed(String cacheKey) {
    _syncConfigChange();
    _failedAt[cacheKey] = DateTime.now();
  }

  /// ⭐ 清理入口 ✓：SMB 服务器配置变更 / 换盘 / 手动清缓存后调用 ⇒ 允许重新尝试 ✓。
  ///
  /// 调用点 ✓：设置页「重置 SMB 连接」经 `ReaderImageProvider.resetSmbRuntime()` 调用 ✓
  ///（`reader_image.dart` ✓）；配置变更则由 [_syncConfigChange] 自动兜住 ✓。
  static void clearFailures() => _failedAt.clear();

  /// 配置变更检测 ✓（identity 比较 ✓：设置写入是整体替换列表 ✓）。
  static void _syncConfigChange() {
    final raw = appdata.settings['smbServers'];
    if (!identical(raw, _serversSignature)) {
      _serversSignature = raw;
      _failedAt.clear();
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
    if (comic.comicType == ComicType.smb ||
        comic.baseDir.startsWith('smb://')) {
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

  /// ⭐ 2026-10-25：**已知缺失封面**缓存已上移到 [SmbCoverLoader] ✓ ——
  /// 与历史封面共用同一份 ✓（原先各持一套 ⇒ 失败记录不共享 ✗）。

  Future<Uint8List> _loadSmbCover() async {
    // Check disk cache first
    final cacheKey = SmbCoverLoader.cacheKey(comic.id, baseDir: comic.baseDir);
    if (SmbCoverLoader.isFailed(cacheKey)) {
      throw "Invalid Status Code: 404 (SMB cover missing, cached failure)";
    }
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

    final client = SmbClient.shared(config);
    await SmbCoverLoader.semaphore.acquire();
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
        final List<SmbEntry> entries;
        try {
          entries = await client.listDirectory(smbDir);
        } on Smb2Exception catch (e) {
          // 目录都不存在（如坏盘漫画 ✓）⇒ 直接判定"封面缺失" ✓，不再重试 ✗。
          if (e.type == Smb2ErrorType.fileNotFound) _failSmbCover(cacheKey);
          rethrow;
        }
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
        final compressed = await compressCoverImage(data);
        await CacheManager().writeCache(cacheKey, compressed);
        return Uint8List.fromList(compressed);
      }
    } finally {
      // ⭐ 共享客户端：**不在此断开** ✓（统一由 SmbClient.closeAllShared / 重置入口管理 ✓）。
      SmbCoverLoader.semaphore.release();
    }
  }

  /// ⭐ 2026-10-25：封面**确定缺失** ⇒ 记住并抛"404" ✓ ——
  /// 上层图片加载看到 `Invalid Status Code: 404` 就**不再重试** ✓（避免反复占用 SMB 连接 ✗）。
  static Never _failSmbCover(String cacheKey) {
    SmbCoverLoader.markFailed(cacheKey);
    throw "Invalid Status Code: 404 (SMB cover missing)";
  }

  /// Compress cover image for cache storage.
  /// Resize to max 512px and encode as JPEG quality 85.
  /// Runs on a background isolate to avoid blocking the UI thread.
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];

  static Future<List<int>> compressCoverImage(Uint8List bytes) {
    return Isolate.run(() {
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return bytes.toList();

        // Resize to max 512px width, keeping aspect ratio via auto-computed height.
        // ⭐ 修复（2026-10-24）：**仅当宽度超限才缩** ✓ ——
        // 原条件含 `height > maxSide` ✗ ⇒ 竖版小图（如 100x1000）会被 `copyResize(width: 512)`
        // **放大** ✗（缓存更大、还糊 ✓）；只按宽度限制也符合 width-only 不变量 ✓。
        final maxSide = 512;
        if (decoded.width > maxSide) {
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

  /// 修复（2026-10-09）：本 provider 的 SMB 封面**磁盘缓存**键不是本类 `key` ✓ ⇒
  /// 原 `delete(key)` 清不掉坏封面缓存（会永久残留、导致坏封面一直加载失败）✗。
  /// 覆写后解码失败的清理即可命中该缓存文件 ✓。
  ///
  /// ⭐ 2026-10-26（P2 ✓）：只保留**带 baseDir 的新键** ✓ —— 原先还会双写一份旧键
  /// `smb_cover:<id>` 以兼容历史页 ✗；历史页的 `cacheKey` 已改为同一个新键 ✓，
  /// 别名写再多一份只是浪费磁盘，且写失败会连带把封面加载**整条拖垮** ✗。
  /// 旧键文件不再写入、也不再读取 ✓（交给 `CacheManager` 的过期/LRU 清理 ✓；
  /// 不做"旧键迁移"✗：旧键按 id 共享，迁移会把**别的漫画的封面**搬到新键上 ✗）。
  @override
  String get cacheKey =>
      SmbCoverLoader.cacheKey(comic.id, baseDir: comic.baseDir);
}
