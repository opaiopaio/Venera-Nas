import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// ⭐ 回归守护（2026-10-10 ✓）：**背景切片必须始终走 `FileImage` 真解析** ✓。
///
/// 背景（血泪教训）✗：`BackgroundSlice` 的模块级缓存 `_sliceCachedImage` 曾被当成**图片来源** ✗
/// ⇒ 命中缓存时**提前 `return`**、跳过 `FileImage.resolve` ✗ ⇒ 用户实测"**每次启动背景图片消失**" ✗，
/// **Android 与 Windows 两端都坏** ✗（缓存里的 `ui.Image` 来自 `ImageInfo`，被释放/淘汰后会失效 ✗，
/// 而缓存只是"免掉那一两帧空窗"的首帧优化 ✓ —— 见 `background_slice.dart` 顶部与 `_resolveImage` 注释 ✓）。
///
/// ⇒ 本文件锁两条互补的不变量 ✓：
/// - **T-BG1（静态）**：命中缓存与 `FileImage(` 之间**不得**出现 `return` ✓；
/// - **T-BG2（行为）**：建一个真实 `BackgroundSlice` ⇒ `FileImage` 必须**照常**进 `ImageCache` ✓
///   （提前返回时这条会红 ✓，已实测 ✓）。
///
/// ⚠️ 冷启动"首帧预加载背景"的尝试（`cbb51a2`）已**整体回退** ✗（用户两次实测背景消失 ✓）——
/// 要重做请先在真机验证，并保证不破坏上面两条 ✓。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('T-BG1 命中缓存处不得提前 return（否则背景永久不再解析 ✗）', () {
    final src = File('lib/components/background_slice.dart').readAsStringSync();
    final code = _stripComments(src);
    final hit = code.indexOf('_image = _sliceCachedImage;');
    expect(hit, isNot(-1), reason: '找不到"首帧命中缓存"分支（结构可能已改，请同步本守卫）');
    final resolve = code.indexOf('FileImage(', hit);
    expect(
      resolve,
      isNot(-1),
      reason: '命中缓存后必须**继续**走 FileImage 解析 ⇒ 否则缓存句柄一旦失效，背景永久消失（曾致两端背景消失 ✗）',
    );
    expect(
      RegExp(r'\breturn\b').hasMatch(code.substring(hit, resolve)),
      isFalse,
      reason: '命中缓存与 FileImage 解析之间出现了 return ✗ ⇒ 会跳过真正的解析（用户实测两端背景图片消失 ✗）',
    );
  });

  testWidgets('T-BG2 命中模块缓存的那一帧仍必须把 FileImage 交给 ImageCache', (tester) async {
    // ⚠️ 2026-10-10（回归审查 P0-2 ✓）：旧版本只泵**一个**新切片 ✗ ⇒ `_sliceCachedImage` 还是 null ✓
    // ⇒ 走的是"无缓存"分支 ✓ ⇒ 把历史那句 `return;` 加回去它**依然是绿** ✓ = **假绿** ✗。
    // 现在改为两步 ✓：① 先泵一个切片并等真实解码完成（模块缓存被填 ✓）；
    // ② 清空 `ImageCache` 后泵**第二个**切片（全新 State ⇒ `_path` 为空而模块缓存已满 ✓）
    // ⇒ 真正进入"命中缓存"分支 ✓ ⇒ 此时 `FileImage` 仍必须进 `ImageCache` ✓（有 `return` 就会红 ✓）。
    final tempDir = Directory.systemTemp.createTempSync('venera-bg-resolve-');
    addTearDown(() {
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    // ⚠️ `App.dataPath` 是 `late` 字段 ✓（未初始化时读会抛 ✗）⇒ 直接赋值 ✓（与既有测试同做法 ✓）。
    App.dataPath = tempDir.path;
    final originalImage = appdata.settings['backgroundImage'];
    final originalColor = appdata.settings['backgroundColor'];
    addTearDown(() {
      appdata.settings['backgroundImage'] = originalImage;
      appdata.settings['backgroundColor'] = originalColor;
    });

    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    File(
      '${dir.path}/bg.png',
    ).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
    appdata.settings['backgroundImage'] = 'bg.png';
    appdata.settings['backgroundColor'] = 'transparent';
    expect(appdata.settings.backgroundFeatureActive, isTrue);

    final provider = FileImage(File('${dir.path}/bg.png'));
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // ① 第一个切片：真实解码（`runAsync` 才能跑真 I/O ✓）⇒ 监听器写入模块缓存 ✓。
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          home: Scaffold(body: BackgroundSlice(key: const ValueKey('first'))),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 80; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (_sliceCacheFilled(provider)) break;
      }
    });
    // 多泵两帧 ✓：让切片的监听器回调真正跑完并写入**模块级缓存** ✓（只等 ImageCache 会太早 ✓）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(
      _sliceCacheFilled(provider),
      isTrue,
      reason: '前置条件：第一个切片必须已把图解码进 ImageCache ✓（否则第二步进不了"命中模块缓存"分支 ✓）',
    );

    // ② 清掉 ImageCache ✓（模块缓存保留 ✓）⇒ 换一个全新 State 的切片 ✓ ⇒ 真正命中缓存分支 ✓。
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    expect(PaintingBinding.instance.imageCache.containsKey(provider), isFalse);

    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          home: Scaffold(body: BackgroundSlice(key: const ValueKey('second'))),
        ),
      ),
    );
    await tester.pump();

    expect(
      PaintingBinding.instance.imageCache.containsKey(provider),
      isTrue,
      reason:
          '命中模块缓存时**也必须继续**把 FileImage 交给 ImageCache 解析 ✗→✓；'
          '若在此处提前 return（历史事故 ✗）⇒ 这里为 false ⇒ "每次启动背景图片消失" 会重现 ✓',
    );
  });
}

/// 模块级缓存是否已被填上（用于等真实解码完成 ✓，不直接读私有变量 ✓）。
bool _sliceCacheFilled(FileImage provider) {
  // 模块缓存写入时必定伴随 `ImageCache` 里有这张图 ✓（两者由同一个监听器一起写 ✓），
  // 且我们只在**清缓存之前**用它做等待判据 ✓。
  return PaintingBinding.instance.imageCache.containsKey(provider);
}

/// 去掉 `//` 行注释与 `/* */` 块注释（避免把注释里的字样当成代码 ✗）。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
