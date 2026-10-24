import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/image_cache_keys.dart';
import 'package:venera_nas/foundation/image_provider/reader_image.dart';

/// ⭐ 2026-10-26：**页缓存键统一**的守护测试 ✓
///
/// 背景：同一串磁盘缓存键原先在阅读器 / 网络图片 / 收藏页各写一遍 ✗ ——
/// 任一处格式漂移都会让"写进去的"和"查出来的"不是同一个文件 ✓
///（历史事故：`smb` / `null` 不一致 ⇒ 收藏 / 保存图片恒报 cache missing ✓）。
///
/// 守护点：
/// 1. 新函数的输出**逐字**保持历史格式 ✓（格式即磁盘缓存协议 ✓，改了等于清缓存 ✓）；
/// 2. `ReaderImageProvider.pageCacheKey` 与统一函数输出一致 ✓（旧 API 仍可用 ✓）；
/// 3. 两个生产文件里**不再出现行内拼装** ✓（静态扫描，防止回退 ✓）。
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

    test('ReaderImageProvider.pageCacheKey 转发后输出一致', () {
      for (final sourceKey in <String?>['s', null]) {
        expect(
          ReaderImageProvider.pageCacheKey('a', sourceKey, 'c', 'e'),
          readerPageCacheKey('a', sourceKey, 'c', 'e'),
          reason: '旧 API 必须与新函数逐字一致（sourceKey=$sourceKey）',
        );
      }
    });

    test('生产文件不再行内拼装页缓存键', () {
      // 原始字符串：避免测试自身触发插值 ✓。
      const needle = r'@$sourceKey@';
      const files = <String>[
        'lib/network/images.dart',
        'lib/pages/reader/images.dart',
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
}
