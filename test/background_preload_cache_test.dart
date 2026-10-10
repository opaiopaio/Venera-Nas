import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// ⭐ 首帧背景图预热守护（2026-10-10 ✓，用户要求补回预热 ✓）。
///
/// 背景 ✓：用户实测"第一次改得更好" ⇒ 第一次同时有**原生窗口底** + **Dart 首帧预热** ✓；
/// 只留原生层时，Flutter 首帧的背景图还没解码好 ✗ ⇒ 占位色（未设底色 = 浅色主题白 ✗）= "白一下" ✓。
///
/// ⚠️ 本次预热刻意**只填 Flutter `ImageCache`** ✓（不自建模块级缓存 ✗、不改 `_resolveImage` ✗）；
/// 图的**真源永远是 widget 自己的 `FileImage` 解析** ✓ ⇒ 上次事故（命中缓存即 `return` 跳过解析 ✗）
/// **结构上不可能重演** ✓。本文件锁三件事 ✓：
/// ① 预热后 `ImageCache` 里必须有该 `FileImage` ✓（旧实现没有预热 ⇒ 必红 ✓）；
/// ② 预热后建**真实** `BackgroundSlice` ⇒ 不得抛异常 ✓（命中缓存会让监听器**同步**回调 ✓，
///   若实现改成"跳过解析/提前 return"之类就会在这里露馅 ✓）；
/// ③ `background_slice.dart` **不得**再出现自建模块级图片缓存字段 ✓（防回退到出事的写法 ✗）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('venera-bgpre-');
    // ⚠️ `App.dataPath` 是 `late` 字段 ✓（未初始化时读会抛 ✗）⇒ 直接赋值 ✓（与既有测试同做法 ✓）。
    App.dataPath = tempDir.path;
    appdata.settings['backgroundColor'] = 'transparent';
    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    File(
      '${dir.path}/bg.png',
    ).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
    appdata.settings['backgroundImage'] = 'bg.png';
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDown(() {
    appdata.settings['backgroundImage'] = '';
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('T-BP1 预热只填 ImageCache，且真实 BackgroundSlice 首帧不抛异常', (
    tester,
  ) async {
    final provider = FileImage(File('${tempDir.path}/background/bg.png'));
    expect(
      PaintingBinding.instance.imageCache.containsKey(provider),
      isFalse,
      reason: '前置条件：预热前缓存里不该有它',
    );

    // 真实异步（读文件 + 解码 ✓）⇒ 必须 `runAsync` ✓，否则 fake async 下会挂死 ✓（已实测）。
    await tester.runAsync(preloadBackgroundImageIntoCache);

    expect(
      PaintingBinding.instance.imageCache.containsKey(provider),
      isTrue,
      reason:
          '预热必须把图片塞进 Flutter 自己的 ImageCache ✓（这样 widget 自己解析时能直接命中 ⇒ 首帧就有图 ✓）；'
          '没有预热时这里为 false ⇒ 首帧只能画占位色（浅色主题=白 ✗）= 用户看到的"白一下" ✓',
    );

    // 建真实切片：命中缓存会让监听器**同步**回调 ⇒ 若有人把解析路径改坏，这里会抛 ✗。
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: const BackgroundSlice())),
      ),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: '预热后建切片不得抛异常 ✓（解析路径必须原样可用 ✓）',
    );
  });

  test('T-BP2 预热必须只走 ImageCache 版实现（防回退到上次出事的写法）', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    final slice = codeOf('lib/components/background_slice.dart');
    // ⚠️ `_sliceCachedImage` 是**图表原有**的首帧缓存 ✓（`57bb869` 保留 ✓，它不跳过解析 ✓，
    // 由 `background_resolve_test.dart` 的 T-BG1/T-BG2 守着 ✓）⇒ 这里**不动它** ✗；
    // 本用例只防"重新引入**旧的自建预热**" ✗（旧实现用 `instantiateImageCodec` 解码进模块缓存 ✓）。
    expect(
      slice.contains('preloadBackgroundImage('),
      isFalse,
      reason: '不得重新引入旧的自建预热函数 ✗（它当年与"命中缓存即 return"配对 ⇒ 出过事故 ✓）',
    );
    expect(
      slice.contains('instantiateImageCodec'),
      isFalse,
      reason: '图片解码不得出现在切片里 ✗（预热只许在 ImageCache 版实现里做 ✓）',
    );
    expect(
      slice.contains('FileImage('),
      isTrue,
      reason: '切片必须继续用 FileImage 真解析 ✓（真源不可变 ✗）',
    );

    final overlay = codeOf('lib/foundation/window_overlay.dart');
    expect(
      overlay.contains('imageCache.containsKey('),
      isTrue,
      reason: '预热必须只填 Flutter 自己的 ImageCache ✓',
    );
    expect(
      overlay.contains('preloadBackgroundImageIntoCache('),
      isTrue,
      reason: '预热入口应在 foundation/window_overlay.dart ✓',
    );
  });
}
