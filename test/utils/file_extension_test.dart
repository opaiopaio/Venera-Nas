import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/utils/io.dart';

/// 回归测试：`File.extension` 必须**统一小写**。
///
/// 此前是 `path.split('.').last`（保留原大小写），而所有调用方都拿它跟小写列表比较：
/// `import_comic.dart` 的 `supportedExtensions`（cbz/zip/7z/cb7）、
/// `imageExtensions`（jpg/png/...）、`local_comic_image.dart` 的 `_imageExtensions`、
/// `epub.dart` 的 `FileType.fromExtension` —— 于是 `foo.JPG` 会被漏判。
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('venera_ext_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File touch(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name')..writeAsStringSync('x');

  test('大写 / 混合大小写扩展名都返回小写', () {
    expect(touch('a.JPG').extension, 'jpg');
    expect(touch('b.PnG').extension, 'png');
    expect(touch('c.WEBP').extension, 'webp');
  });

  test('小写扩展名保持原样（零回归）', () {
    expect(touch('d.jpg').extension, 'jpg');
    expect(touch('e.jpeg').extension, 'jpeg');
  });

  test('漫画包扩展名与 supportedExtensions 的小写列表可直接比较', () {
    const supportedExtensions = ['cbz', 'zip', '7z', 'cb7'];
    expect(supportedExtensions.contains(touch('comic.CBZ').extension), isTrue);
    expect(supportedExtensions.contains(touch('comic.7Z').extension), isTrue);
  });
}
