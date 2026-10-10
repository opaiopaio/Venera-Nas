import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// ⭐ 本轮（用户实测反馈 ✓）回归守护：**冷启动首帧的背景图预加载** ✓。
///
/// 用户原话：「安卓端启动程序的时候，**背景是白色然后闪出背景的**。首帧没有背景的预加载吗？」
/// 真因 ✓：背景图原先只在 `BackgroundSlice` 的 `didChangeDependencies` 里才 `FileImage.resolve` ✓
/// ⇒ 冷启动**首帧没有图** ✗，那一帧只有底色（未设背景色时 = `scheme.surface` = 浅色主题白 ✗）。
/// 修法 ✓：`preloadBackgroundImage()` 在 `runApp` 之前把图解码进**同一个模块级缓存** ✓
///（`lib/components/background_slice.dart` ✓），首个切片的首帧即命中 ✓。
///
/// ⚠️ **血泪教训（2026-10-10 ✓）**：第一版把"命中缓存"当成终态、在 `_resolveImage` 里**提前 `return`** ✗
/// ⇒ 用户实测"**每次启动背景图片消失**" ✗，**Android 与 Windows 两端都坏** ✗。
/// 因此本文件必须覆盖两条**互补**的断言 ✓：
/// ① 预热确实能解码 ✓（下面 3 条 ✓）；
/// ② 预热之后**背景仍然被正确解析** ✓（T-BG4 ✓：`FileImage` 必须照常进 `ImageCache` ✓）；
/// ③ 静态守卫：命中缓存处**不得**出现提前 `return` ✓（T-BG3 ✓）。
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

  test('T-BG3 命中缓存处**不得**提前 return（否则背景永久不再解析 ✗）', () {
    final src = File('lib/components/background_slice.dart').readAsStringSync();
    final code = _stripComments(src);
    final hit = code.indexOf('_image = _sliceCachedImage;');
    expect(hit, isNot(-1), reason: '找不到"首帧命中缓存"分支（结构可能已改，请同步本守卫）');
    final resolve = code.indexOf('FileImage(', hit);
    expect(
      resolve,
      isNot(-1),
      reason: '命中缓存后必须**继续**走 FileImage 解析 ⇒ 否则缓存句柄一旦失效，背景永久消失（本次回归 ✗）',
    );
    expect(
      RegExp(r'\breturn\b').hasMatch(code.substring(hit, resolve)),
      isFalse,
      reason:
          '命中缓存与 FileImage 解析之间出现了 return ✗ ⇒ 会跳过真正的解析'
          '（用户实测：Android 与 Windows 两端背景图片消失 ✗）',
    );
  });

  testWidgets('T-BG4 预热之后背景**仍被正确解析**（FileImage 照常进 ImageCache ✓）', (
    tester,
  ) async {
    // 这条正是上一轮漏掉的断言 ✓：只测"预热能解码" ✗ 测不出"预热把真解析挡掉了" ✗。
    writeBackgroundImage('bg_resolve.png');
    appdata.settings['backgroundImage'] = 'bg_resolve.png';
    appdata.settings['backgroundColor'] = 'transparent';

    final file = File('${tempDir.path}/background/bg_resolve.png');
    final provider = FileImage(file);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 预热 ✓（首帧优化的那一半 ✓）。
    // ⚠️ 真实异步（读文件 + 解码 ✓）必须放 `runAsync` ✗→✓，否则 fake async 下会**挂死** ✓（已实测）。
    final preloaded = await tester.runAsync(() => preloadBackgroundImage());
    expect(preloaded, isNotNull);

    // 建一个真实切片 ✓ ⇒ `_resolveImage` 必须**照常**把 FileImage 交给 ImageCache ✓。
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: const BackgroundSlice())),
      ),
    );
    await tester.pump();

    expect(
      PaintingBinding.instance.imageCache.containsKey(provider),
      isTrue,
      reason:
          '命中模块级缓存后没有再走 FileImage 解析 ✗ ⇒ 缓存的 ui.Image 一旦失效，'
          '背景就永久画不出来（用户实测两端背景消失 ✗）',
    );
  });
}

/// 去掉 `//` 行注释与 `/* */` 块注释（避免把注释里的字样当成代码 ✗）。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
