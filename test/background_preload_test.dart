import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// ⭐ 本轮（用户实测反馈 ✓）回归守护：**冷启动首帧的背景图预加载** ✓。
///
/// 用户原话：「安卓端启动程序的时候，**背景是白色然后闪出背景的**。首帧没有背景的预加载吗？」
/// 真因 ✓：背景图原先只在 `BackgroundSlice` 的 `didChangeDependencies` 里才 `FileImage.resolve` ✓
/// ⇒ 冷启动**首帧没有图** ✗，那一帧只有底色（未设背景色时 = `scheme.surface` = 浅色主题白 ✗）。
/// 修法 ✓：`preloadBackgroundImage()` 在 `runApp` 之前把图解码进**同一个模块级缓存** ✓
///（`lib/components/background_slice.dart` ✓），首个切片的首帧即命中 ✓ 且不再重复解码 ✓。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Object? originalImage;
  late Object? originalColor;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('venera-bg-preload-');
    // ⚠️ `App.dataPath` 是 `late` 字段 ✓（未初始化时**读**它会抛 ✗）⇒ 直接赋值 ✓，
    // 与既有测试（`favorites_follow_updates_test.dart` ✓）同一做法 ✓；本文件内每个用例各自设置 ✓。
    App.dataPath = tempDir.path;
    originalImage = appdata.settings['backgroundImage'];
    originalColor = appdata.settings['backgroundColor'];
  });

  tearDown(() {
    appdata.settings['backgroundImage'] = originalImage;
    appdata.settings['backgroundColor'] = originalColor;
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 在 `<dataPath>/background/` 下放一张真实可解码的小 PNG ✓。
  void writeBackgroundImage(String name) {
    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    final png = img.encodePng(img.Image(width: 4, height: 4));
    File('${dir.path}/$name').writeAsBytesSync(png);
  }

  test('未配置背景 → 预加载返回 null（不产生任何副作用 ✓）', () async {
    appdata.settings['backgroundImage'] = '';
    appdata.settings['backgroundColor'] = 'transparent';
    expect(await preloadBackgroundImage(), isNull);
  });

  test('配置了背景图 → 预加载成功解码，且重复调用命中缓存（不重复解码 ✓）', () async {
    writeBackgroundImage('bg_test.png');
    appdata.settings['backgroundImage'] = 'bg_test.png';
    appdata.settings['backgroundColor'] = 'transparent';
    // 让 `AppBackground.isActive` 成立（有图即算启用 ✓）。
    expect(appdata.settings.backgroundFeatureActive, isTrue);

    final first = await preloadBackgroundImage();
    expect(first, isNotNull, reason: '首帧预加载没有拿到解码结果 ⇒ 冷启动首帧仍会露底色');
    expect(first!.width, 4);
    expect(first.height, 4);

    final second = await preloadBackgroundImage();
    expect(
      identical(first, second),
      isTrue,
      reason: '重复调用应命中模块级缓存 ⇒ 不重复解码（启动开销只付一次 ✓）',
    );
  });

  test('背景图文件缺失/损坏 → 返回 null 且不抛（回退为底色 ✓，绝不拖垮启动 ✓）', () async {
    appdata.settings['backgroundImage'] = 'not_exists.png';
    appdata.settings['backgroundColor'] = 'transparent';
    expect(await preloadBackgroundImage(), isNull);

    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    File('${dir.path}/broken.png').writeAsBytesSync(<int>[1, 2, 3, 4, 5]);
    appdata.settings['backgroundImage'] = 'broken.png';
    expect(await preloadBackgroundImage(), isNull);
  });
}
