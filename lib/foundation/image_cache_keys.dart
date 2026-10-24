/// ⭐ 2026-10-26：**页缓存键的统一拼装出口** ✓
///
/// 为什么单独成文件 ✓：同一套键格式原先在 `reader_image.dart`、
/// `pages/reader/images.dart`、`network/images.dart`、`image_favorites_provider.dart`
/// 里各写一遍 ✗ ⇒ 任一处漏改就会"写进去的和查出来的不是同一个文件" ✗
///（历史上已踩过 `@smb@` / `@null@` 不一致 ⇒ 收藏 / 保存图片恒报 cache missing ✓）。
///
/// ⚠️ **格式是磁盘缓存协议的一部分** ✗ —— 分隔符、字段顺序、以及 `sourceKey == null`
/// 时插值成字符串 `null` 的方式，一旦改动就等于**清空所有用户已有的页缓存** ✓
///（旧文件再也命中不到 ✓）。因此本文件只做**逐字字符串拼接** ✓：
/// 不加编码、不加版本号、不换分隔符 ✗。
library;

/// 阅读器**单页图片**的磁盘缓存键 ✓。
///
/// 格式：`$imageKey@$sourceKey@$cid@$eid`（`sourceKey` 为 null 时得到 `@null@` ✓）。
/// 必须与 `network/images.dart` 的磁盘读写、`ReaderImageProvider.cacheKey`、
/// 收藏页 / 保存图片的查缓存**逐字一致** ✓。
String readerPageCacheKey(
  String imageKey,
  String? sourceKey,
  String cid,
  String eid,
) => "$imageKey@$sourceKey@$cid@$eid";

/// 阅读器**页列表**的磁盘缓存键 ✓（前缀 `loadComicPages@` 保持原样 ✓）。
///
/// 格式：`loadComicPages@$sourceKey@$cid@$eid`。
/// ⚠️ 调用方传入的 `sourceKey` 语义不同（SMB 页列表写入用 `type.sourceKey`
/// 即 `'smb'` ✓，provider 侧清理用 `comicSource?.key` 即 `null` ✓）——
/// 本函数只负责拼接，**不替调用方决定传哪个** ✓（两者都是既有协议的一部分 ✓）。
String comicPagesListCacheKey(String? sourceKey, String cid, String eid) =>
    "loadComicPages@$sourceKey@$cid@$eid";

/// **缩略图**（封面 / 收藏封面）的磁盘缓存键 ✓。
///
/// 格式：`$url@$sourceKey`；给了 [cid] 时追加 `@$cid` ✓（否则不追加 ✓）。
/// ⚠️ 三处消费方必须逐字一致 ✓ —— `network/images.dart` 的 `loadThumbnail`
/// 负责读写，`CachedImageProvider.cacheKey` 与 `LocalFavoriteImageProvider.cacheKey`
/// 负责解码失败时删除 ✓（删错键 ⇒ 坏封面永久残留 ✗）。
///
/// ⚠️ 格式同样是磁盘缓存协议 ✓ —— `null` 会插值成字符串 `null` ✓，不要改动 ✗。
String thumbnailCacheKey(String url, String? sourceKey, [String? cid]) =>
    "$url@$sourceKey${cid != null ? '@$cid' : ''}";
