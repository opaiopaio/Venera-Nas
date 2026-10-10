import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// ⭐ 回归守护（2026-10-10 ✓）：**「设备特定设置」开启写入的值，重启后必须仍能读到** ✓。
///
/// 用户三步对照实验（原话要点 ✓）：
/// ① 清除本设备设置 ⇒ 开关自动关 ✓（`resetDeviceSpecificSettings` 删整条 ✓，含 `enabledAppearance` ✓，符合预期 ✓）；
/// ② **开关关**时设背景 ⇒ 重启**正常** ✓（值落**全局层** ✓）；
/// ③ **开关开**时设背景 ⇒ **重启后背景消失** ✗（双端 ✓，`+80` 亦可复现 ⇒ 与冷启动改动无关 ✓）。
///
/// 根因 ✓（`appdata.dart` ✓）：开开关时值**只落设备层** ✓（设计使然 ✓ —— 不能被同步/恢复覆盖 ✓，
/// 且全局层必须保持"共享基线" ✓，否则 `device_settings_gate_test.dart` 的 T-DS2/T-DS4 语义被破坏 ✗），
/// 而设备层按 `deviceId` 分键 ✓ ⇒ `deviceId` 一旦变化过（旧版本被 WebDAV 恢复整文件覆盖 `appdata.json`
/// 从而丢过 `deviceId` ✗、或生成后未落盘就被杀 ✓），原条目即成**孤儿** ✗ ⇒ 读取静默回落到**全局空值** ✗
/// ⇒ 背景"**永久消失**" ✓，开关也会同源读成 false ✓。
/// 修法 ✓：`Appdata.doInit()` 在 `deviceId` 就位后**回收孤儿条目** ✓（重新挂到当前 id ✓，
/// 见 `appdata.dart` 的 `_adoptOrphanDeviceEntry` ✓）。
///
/// 本文件锁两条不变量 ✓：
/// - **T-DS1**：开关开 → 写背景 → 存盘 ⇒ 值在**设备层** ✓、**不污染全局层** ✓（既有设计不变 ✓）；
/// - **T-DS2**：**`deviceId` 变化后重启** ⇒ 值必须仍在 ✓（旧版会读到空 ⇒ 必红 ✓ 已实测 ✓）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dataFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-devpersist-');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    // ⚠️ `App.dataPath` 是 `late` 字段 ✓（未初始化时读会抛 ✗）⇒ 直接赋值 ✓（与既有测试同做法 ✓）。
    App.dataPath = tempDir.path;
    dataFile = File('${tempDir.path}/appdata.json');
    appdata.settings.resetDeviceSpecificSettings();
    await appdata.init();
  });

  tearDown(() {
    appdata.settings.resetDeviceSpecificSettings();
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['backgroundImage'] = '';
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> readSavedSettings() {
    final json = jsonDecode(dataFile.readAsStringSync()) as Map;
    return Map<String, dynamic>.from(json['settings'] as Map);
  }

  void writeSavedSettings(Map<String, dynamic> settings) {
    final json = jsonDecode(dataFile.readAsStringSync()) as Map;
    json['settings'] = settings;
    dataFile.writeAsStringSync(jsonEncode(json));
  }

  /// 开关**开**着设背景 ✓（= 用户第 ③ 步 ✓）：造真实图片文件 + 写设置 + 落盘 ✓。
  Future<void> setBackgroundWithDeviceSwitchOn() async {
    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    File(
      '${dir.path}/bg.png',
    ).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings['backgroundImage'] = 'bg.png';
    appdata.settings['backgroundImageSource'] = '/src/bg.png';
    await appdata.saveData(false);
  }

  test('T-DS1 开关开启时写入落设备层，且不污染全局层（既有设计 ✓）', () async {
    await setBackgroundWithDeviceSwitchOn();

    final saved = readSavedSettings();
    final deviceId = saved['deviceId'] as String;
    final table = (saved['deviceSpecificSettings'] as Map)[deviceId] as Map?;
    expect(deviceId, isNotEmpty, reason: 'deviceId 必须落盘');
    expect(table?['enabledAppearance'], isTrue, reason: '开关状态必须落盘');
    expect(table?['backgroundImage'], 'bg.png', reason: '设备层应保存本设备覆盖值');
    expect(
      saved['backgroundImage'],
      isNot('bg.png'),
      reason:
          '设备层写入**不得**污染全局层 ✓ —— 全局层是"共享基线" ✓，'
          '清除本设备设置后必须能回落到它（T-DS2/T-DS4 的既有语义 ✓）',
    );
  });

  test('T-DS2 deviceId 变化后重启，设备专属值仍可读（旧版必红）', () async {
    await setBackgroundWithDeviceSwitchOn();
    expect(appdata.settings['backgroundImage'], 'bg.png');

    // ① 模拟"旧版本曾把 deviceId 弄丢"：把存档里的 deviceId 写空 ✓（设备条目仍在表里 ✓ = 孤儿 ✓）。
    final saved = readSavedSettings();
    saved['deviceId'] = '';
    writeSavedSettings(saved);

    // ② 重启：重新读同一份存储 ✓。
    // ⚠️ 必须直接调 `doInit()` ✗→✓（基类 `init()` 带幂等守卫 ⇒ 不会真的重读 ✗，实测证明 ✗）；
    //    `doInit` 会把内存里的 id 也置空 ✓、随后生成新 id ✓ 并回收孤儿条目 ✓。
    await appdata.doInit();

    final newId = appdata.settings['deviceId'] as String;
    expect(newId, isNotEmpty, reason: '重启后应生成新的 deviceId');

    // ③ 关键断言 ✓：值必须仍读得到 ✓（旧版：新 id 无条目 ⇒ 回落全局空值 ⇒ 必红 ✗）。
    expect(
      appdata.settings['backgroundImage'],
      'bg.png',
      reason:
          'deviceId 变化后设备条目成孤儿 ⇒ 读取静默回落为空 ⇒ 用户实测'
          '"开开关设背景 ⇒ 重启后背景消失"（双端 ✗，+80 亦可复现 ✓）',
    );
    expect(
      appdata.settings.isAppearanceDeviceSettingsEnabled(),
      isTrue,
      reason: '开关状态随条目一起被认领 ✓ ⇒ 不该无缘无故复位',
    );
    // 认领后必须立刻落盘 ✓（下次启动直接可用 ✓）。
    final savedAgain = readSavedSettings();
    expect(
      ((savedAgain['deviceSpecificSettings'] as Map)[newId]
          as Map?)?['backgroundImage'],
      'bg.png',
      reason: '认领结果必须落盘 ⇒ 否则每次启动都要重新认领一次',
    );
  });
}
