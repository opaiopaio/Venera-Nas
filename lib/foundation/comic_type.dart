import 'package:venera/foundation/comic_source/comic_source.dart';

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
      return comicSource!.key;
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
}
