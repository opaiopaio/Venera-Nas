import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⭐ 安卓冷启动窗口底（原生层）静态守护（2026-10-10 ✓）。
///
/// 背景 ✓：用户要求"启动瞬间就是背景" ✓ —— 修法是**只改 Android 原生一层** ✓：
/// `MainActivity` 读 Dart 侧同一份 `appdata.json`（顶层 `settings` ✓）把已保存的背景铺到 `windowBackground` ✓
/// （`res/values/styles.xml` 的注释写明该层就是"Flutter UI 初始化期间"可见的那一层 ✓，
/// 而 `drawable/launch_background.xml` 写死白色 ✗ ⇒ 先白后出图 ✓）。
///
/// 本守护锁两条**最关键的纪律** ✓：
/// ① **只读** ✗：该功能段内**不得**出现任何写/删/改名/建目录的 API ✓
///   （用户前几次事故都源于"启动期动了用户数据" ✓）；
/// ② 读的键/路径必须与 Dart 侧一致 ✓：`appdata.json` 的顶层 `settings.backgroundImage` /
///   `settings.backgroundColor` ✓ 与 `<filesDir>/background/` ✓（`appdata.dart:33`/`:78-79`/`:343` ✓、
///   `window_overlay.dart:29-34` ✓）—— **不得**再出现已废弃的 `deviceSpecificSettings` 设备层查找 ✗。
void main() {
  late String src;

  setUpAll(() {
    final f = File(
      'android/app/src/main/kotlin/io/github/opaiopaio/veneranas/MainActivity.kt',
    );
    expect(f.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');
    src = f.readAsStringSync();
  });

  test('T-LB1 启动窗口底功能段必须只读（无任何写入/删除/建目录 API）', () {
    // ⚠️ 必须先**去注释** ✗→✓：本段代码注释里刻意写了"不该出现哪些写入 API" ✓，
    // 不去注释会自我误报 ✗（本项目既有静态守卫同款做法 ✓，见 `ap1_static_regression_test.dart` ✓）。
    final code = _stripComments(src);
    final start = code.indexOf('private var launchBackground');
    expect(start, isNot(-1), reason: '找不到启动窗口底功能段（结构可能已改，请同步本守卫）');
    final end = code.indexOf('override fun onKeyDown', start);
    expect(end, isNot(-1), reason: '功能段未正常结束');
    final block = code.substring(start, end);

    for (final banned in const <String>[
      'FileOutputStream',
      'openFileOutput',
      'writeBytes',
      'writeText',
      'createNewFile',
      'renameTo',
      'mkdir',
      '.delete(',
      'deleteRecursively',
    ]) {
      expect(
        block.contains(banned),
        isFalse,
        reason: '启动窗口底这段**只允许读** ✗ —— 出现 `$banned` 意味着启动期会动用户文件（历史事故根源 ✓）',
      );
    }
    // 正例：确实用只读 API 读同一份存储 ✓。
    expect(
      block.contains('readText()'),
      isTrue,
      reason: '应从 appdata.json 读取设置 ✓',
    );
    expect(
      block.contains('BitmapFactory.decodeFile'),
      isTrue,
      reason: '背景图应采样解码后铺到窗口底 ✓',
    );
  });

  test('T-LB2 只读顶层 settings 的键，且不得再查已废弃的设备层', () {
    final code = _stripComments(src);
    final start = code.indexOf('private var launchBackground');
    final end = code.indexOf('override fun onKeyDown', start);
    final block = code.substring(start, end);

    expect(block.contains('optJSONObject("settings")'), isTrue);
    expect(block.contains('"backgroundImage"'), isTrue);
    expect(block.contains('"backgroundColor"'), isTrue);
    expect(
      block.contains('deviceSpecificSettings'),
      isFalse,
      reason:
          '设备设置已按用户方案重构为"只有一套值"（全部在顶层 settings ✓）⇒ '
          '原生侧不得再做设备层查找 ✗',
    );
  });
}

/// 去掉 `//` 行注释与 `/* */` 块注释（避免把注释里的字样当成代码 ✗）。
String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');
