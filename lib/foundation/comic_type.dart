import 'package:venera_nas/foundation/comic_source/comic_source.dart';

class ComicType {
  final int value;

  const ComicType(this.value);

  @override
  bool operator ==(Object other) => other is ComicType && other.value == value;

  @override
  int get hashCode => value.hashCode;

  String get sourceKey {
    if (this == local) {
      return "local";
    } else if (this == smb) {
      return "smb";
    } else {
      return comicSource?.key ?? "Unknown:$value";
    }
  }

  ComicSource? get comicSource {
    if (this == local || this == smb) {
      return null;
    } else {
      return ComicSource.fromIntKey(value);
    }
  }

  static const local = ComicType(0);

  static const smb = ComicType(-1);

  factory ComicType.fromKey(String key) {
    if (key == "local") {
      return local;
    } else if (key == "smb") {
      return smb;
    } else {
      return ComicType(key.hashCode);
    }
  }

  /// ⭐ 2026-10-24：**从历史/收藏条目里的 `sourceKey` 反推 ComicType** ✓
  ///
  /// 为什么单独抽出来 ✓：这段逻辑原先写在 `pages/history_page.dart` 的 `_removeHistory` 里 ✓，
  /// 是"**删不掉 SMB 历史**"这类 bug 的唯一判定点 ✓ ⇒ 抽成纯函数后可直接单测 ✓
  ///（`test/comic_type_smb_test.dart` ✓ 守护"smb 必须映射到 [smb]（value -1）"✓，防止再被改成 `'smb'.hashCode` ✗）。
  ///
  /// - `Unknown:<value>` ⇒ 未知源（历史里存的兜底格式 ✓）
  /// - `local` / `smb` ⇒ 对应内置类型 ✓
  /// - 其它 ⇒ 网络漫画源 key ✓
  static ComicType fromHistorySourceKey(String sourceKey) {
    if (sourceKey.startsWith("Unknown:")) {
      final parts = sourceKey.split(':');
      if (parts.length > 1) {
        final value = int.tryParse(parts[1]);
        if (value != null) {
          return ComicType(value);
        }
      }
    }
    return ComicType.fromKey(sourceKey);
  }
}
