import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/history.dart';
import 'package:venera_nas/foundation/image_cache_keys.dart';
import 'package:venera_nas/foundation/image_provider/image_favorites_provider.dart';
import 'package:venera_nas/foundation/image_provider/reader_image.dart';

/// ⭐ 2026-10-26：**缓存键统一**的守护测试 ✓
///
/// 背景：同一串磁盘缓存键原先在阅读器 / 网络图片 / 收藏页各写一遍 ✗ ——
/// 任一处格式漂移都会让"写进去的"和"查出来的"不是同一个文件 ✓
///（历史事故：`smb` / `null` 不一致 ⇒ 收藏 / 保存图片恒报 cache missing ✓）。
///
/// 守护点：
/// 1. 三个统一函数的输出**逐字**保持历史格式 ✓（格式即磁盘缓存协议 ✓，改了等于清缓存 ✓）；
/// 2. `ReaderImageProvider.pageCacheKey` 与统一函数输出一致 ✓（旧 API 仍可用 ✓）；
/// 3. SMB 图片收藏的 `cacheKey` 必须把 `sourceKey` 归一为 null ✓（与阅读器落盘键一致 ✓）；
/// 4. **所有**使用 `CacheManager` 的生产文件都在白名单内 ✓ —— 新增调用点必须评审键的来源 ✓；
/// 5. 各图片缓存生产文件都改用了统一函数 ✓，旧的行内拼装不再出现 ✓。
void main() {
  group('页缓存键统一', () {
    test('readerPageCacheKey 保持原格式（sourceKey 为 null ⇒ null 字符串）', () {
      expect(readerPageCacheKey('a', 's', 'c', 'e'), 'a@s@c@e');
      expect(readerPageCacheKey('a', null, 'c', 'e'), 'a@null@c@e');
    });

    test('comicPagesListCacheKey 前缀 loadComicPages@ 与字段顺序不变', () {
      expect(comicPagesListCacheKey('s', 'c', 'e'), 'loadComicPages@s@c@e');
      expect(comicPagesListCacheKey(null, 'c', 'e'), 'loadComicPages@null@c@e');
    });

    test('thumbnailCacheKey 保持原格式（cid 为 null 时不追加 @cid）', () {
      expect(thumbnailCacheKey('u', 's'), 'u@s');
      expect(thumbnailCacheKey('u', null), 'u@null');
      expect(thumbnailCacheKey('u', 's', 'c'), 'u@s@c');
      expect(thumbnailCacheKey('u', null, 'c'), 'u@null@c');
    });

    test('ReaderImageProvider.pageCacheKey 转发后输出一致', () {
      for (final sourceKey in <String?>['s', null]) {
        expect(
          ReaderImageProvider.pageCacheKey('a', sourceKey, 'c', 'e'),
          readerPageCacheKey('a', sourceKey, 'c', 'e'),
          reason: '旧 API 必须与新函数逐字一致（sourceKey=$sourceKey）',
        );
      }
    });

    test('SMB 图片收藏的 cacheKey 把 sourceKey 归一为 null', () {
      const imageKey = 'smb://nas/share/Comic/Chapter1/003.jpg';
      final favorite = ImageFavorite(
        3,
        imageKey,
        null,
        'chapter-eid',
        'comic-id',
        1,
        'smb',
        'Chapter 1',
      );
      expect(
        ImageFavoritesProvider(favorite).cacheKey,
        readerPageCacheKey(imageKey, null, 'comic-id', 'chapter-eid'),
        reason: 'SMB 没有 ComicSource ⇒ 阅读器落盘键是 @null@，收藏必须一致',
      );
    });

    test('非 SMB 收藏的 cacheKey 保持原有 sourceKey', () {
      final favorite = ImageFavorite(
        1,
        'image-key',
        null,
        'eid',
        'cid',
        1,
        'source-key',
        'E1',
      );
      expect(
        ImageFavoritesProvider(favorite).cacheKey,
        readerPageCacheKey('image-key', 'source-key', 'cid', 'eid'),
      );
    });

    test('生产文件不再行内拼装页缓存键', () {
      // 原始字符串：避免测试自身触发插值 ✓。
      const needle = r'@$sourceKey@';
      const files = <String>[
        'lib/network/images.dart',
        'lib/pages/reader/images.dart',
        'lib/foundation/image_provider/image_favorites_provider.dart',
      ];
      for (final path in files) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '源文件不存在：$path');
        expect(
          file.readAsStringSync().contains(needle),
          isFalse,
          reason: '$path 里仍有行内缓存键拼装，请改用 image_cache_keys.dart',
        );
      }
    });
  });

  group('缓存键调用点白名单', () {
    // ⭐ 所有直接使用 `CacheManager` 的生产文件 ✓（网络缓存的
    // `NetworkCacheManager` 不在此列 ✓ —— 它是另一套内存缓存 ✓）。
    // 新增文件 ⇒ 本用例变红 ⇒ 必须先确认它用的是统一函数（或明确属于非图片缓存）✓。
    const cacheManagerFiles = <String>{
      'lib/init.dart',
      'lib/foundation/cache_manager.dart',
      'lib/foundation/image_provider/base_image_provider.dart',
      'lib/foundation/image_provider/history_image_provider.dart',
      'lib/foundation/image_provider/image_favorites_provider.dart',
      'lib/foundation/image_provider/local_comic_image.dart',
      'lib/foundation/image_provider/reader_image.dart',
      'lib/network/images.dart',
      'lib/pages/reader/comic_image.dart',
      'lib/pages/reader/images.dart',
      'lib/pages/reader/scaffold.dart',
      'lib/pages/settings/app.dart',
    };

    test('所有使用 CacheManager 的生产文件都在白名单内', () {
      // 负向后行断言：排除 `NetworkCacheManager()` ✓。
      final cacheManagerCall = RegExp(r'(?<![A-Za-z])CacheManager\(\)');
      final found = <String>{};
      for (final file in _dartFiles('lib')) {
        if (cacheManagerCall.hasMatch(file.readAsStringSync())) {
          found.add(_relativePath(file));
        }
      }
      expect(
        found.difference(cacheManagerFiles),
        isEmpty,
        reason: '新增了 CacheManager 调用点：请确认键的拼装方式并更新白名单',
      );
    });

    test('图片缓存生产文件都走统一函数', () {
      const expected = <String, List<String>>{
        'lib/network/images.dart': [
          'thumbnailCacheKey(',
          'readerPageCacheKey(',
        ],
        'lib/foundation/image_provider/reader_image.dart': [
          'readerPageCacheKey(',
        ],
        'lib/foundation/image_provider/image_favorites_provider.dart': [
          'readerPageCacheKey(',
        ],
        'lib/foundation/image_provider/cached_image.dart': [
          'thumbnailCacheKey(',
        ],
        'lib/foundation/image_provider/local_favorite_image.dart': [
          'thumbnailCacheKey(',
        ],
        'lib/foundation/image_provider/history_image_provider.dart': [
          'SmbCoverLoader.cacheKey(',
        ],
        'lib/foundation/image_provider/local_comic_image.dart': [
          'SmbCoverLoader.cacheKey(',
        ],
        'lib/pages/reader/images.dart': ['comicPagesListCacheKey('],
        'lib/pages/reader/comic_image.dart': ['comicPagesListCacheKey('],
      };
      for (final entry in expected.entries) {
        final file = File(entry.key);
        expect(file.existsSync(), isTrue, reason: '源文件不存在：${entry.key}');
        final source = file.readAsStringSync();
        for (final needle in entry.value) {
          expect(
            source.contains(needle),
            isTrue,
            reason: '${entry.key} 未使用统一函数 $needle',
          );
        }
      }
    });

    test('旧的行内缩略图键拼装不再出现', () {
      // 原始字符串：避免测试自身触发插值 ✓。
      const forbidden = <String>[
        r'"$url@$sourceKey',
        r'"$url@${ComicSource.fromIntKey',
        r'"$imageKey@$sourceKey@$cid@$eid"',
      ];
      for (final file in _dartFiles('lib')) {
        final path = _relativePath(file);
        if (path == 'lib/foundation/image_cache_keys.dart') continue;
        final source = file.readAsStringSync();
        for (final needle in forbidden) {
          expect(
            source.contains(needle),
            isFalse,
            reason: '$path 里仍有行内缓存键拼装：$needle',
          );
        }
      }
    });
  });
}

Iterable<File> _dartFiles(String root) sync* {
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

String _relativePath(File file) => file.path.replaceAll(r'\', '/');
