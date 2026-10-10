import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// ⭐ 设备开关的**门控行为**测试（2026-10-10 ✓，按用户方案重构后的新语义 ✓）。
///
/// **新语义** ✓（用户原话："不能做成就是**保持现在的设置**，但是**阻隔同步和备份**吗" ✓）：
/// - 所有设置**只有一套值** ✓（主表 `_data` ✓，不再有 `deviceSpecificSettings` 第二层 ✗）；
/// - 两个开关是**纯标志** ✓：只表示"对应的键在本设备**不参与同步 / 备份 / 恢复**" ✓；
/// - ⇒ **翻转开关不改变任何读写语义** ✓ ⇒ 值不可能因为切开关而丢 ✓。
///
/// 本测试锁定三件事 ✓：
/// ① 归属划分正确 ✓；② 开关 ON ⇒ 受保护键被同步/恢复排除 ✓、OFF ⇒ 正常参与 ✓；
/// ③ "清除本设备设置"只关开关、**值全部保留** ✓。
void main() {
  const touchedKeys = <String>[
    'color',
    'globalIconColor',
    'theme_mode',
    'readerMode',
    'enablePageAnimation',
    'customImageProcessing',
    'language',
    'historyRetentionDays',
  ];

  final original = <String, dynamic>{};
  late bool origAppearanceGate;
  late bool origReaderGate;
  late Directory tempDir;

  setUp(() {
    // `syncData`/`restoreFromBackup` 内部会 `saveData()` ⇒ 需要可用的 `App.dataPath` ✓。
    tempDir = Directory.systemTemp.createTempSync('venera-gate-');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    App.dataPath = tempDir.path;
    for (final k in touchedKeys) {
      original[k] = appdata.settings[k];
    }
    origAppearanceGate = appdata.settings.isAppearanceDeviceSettingsEnabled();
    origReaderGate = appdata.settings.isDeviceSpecificSettingsEnabled();
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
    for (final k in touchedKeys) {
      appdata.settings[k] = original[k];
    }
    appdata.settings.setEnabledAppearanceDeviceSettings(origAppearanceGate);
    appdata.settings.setEnabledDeviceSpecificSettings(origReaderGate);
  });

  test('T-DS1：三组归属划分正确（外观 / 阅读 / 其余）', () {
    expect(appdata.settings.isDeviceProtected('color'), isFalse);
    expect(appdata.settings.isDeviceProtected('readerMode'), isFalse);

    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    expect(appdata.settings.isDeviceProtected('color'), isTrue);
    expect(appdata.settings.isDeviceProtected('globalIconColor'), isTrue);
    expect(appdata.settings.isDeviceProtected('theme_mode'), isTrue);
    expect(
      appdata.settings.isDeviceProtected('readerMode'),
      isFalse,
      reason: '阅读键不该被外观开关管',
    );

    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    expect(appdata.settings.isDeviceProtected('readerMode'), isTrue);
    expect(appdata.settings.isDeviceProtected('customImageProcessing'), isTrue);
    expect(
      appdata.settings.isDeviceProtected('color'),
      isFalse,
      reason: '外观键不该被阅读开关管',
    );

    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    for (final k in <String>[
      'language',
      'historyRetentionDays',
      'smbServers',
      'backupWebdav',
    ]) {
      expect(
        appdata.settings.isDeviceProtected(k),
        isFalse,
        reason: '其余页面的设置（$k）不应受任何设备开关影响',
      );
    }
  });

  test('T-DS2：开关 ON ⇒ 受保护键被同步/恢复排除（值仍在本机主表 ✓）', () {
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings['color'] = 'LOCAL';
    appdata.settings['language'] = 'en';

    appdata.syncData(<String, dynamic>{
      'settings': <String, dynamic>{'color': 'CLOUD', 'language': 'zh-CN'},
    });
    appdata.restoreFromBackup(<String, dynamic>{
      'settings': <String, dynamic>{'color': 'BACKUP'},
    });

    expect(
      appdata.settings['color'],
      'LOCAL',
      reason: '开关 ON 的受保护键必须不参与同步/恢复（这就是该开关的全部作用 ✓）',
    );
    expect(appdata.settings['language'], 'zh-CN', reason: '非受保护键照常参与同步 ✓');
    expect(
      appdata.settings['deviceSpecificSettings'],
      isEmpty,
      reason: '新语义下**没有第二层存储** ✓（值只在主表 ✓）',
    );
  });

  test('T-DS3：开关 OFF ⇒ 正常参与同步（与改造前一致 ✓）', () {
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['color'] = 'LOCAL';
    appdata.syncData(<String, dynamic>{
      'settings': <String, dynamic>{'color': 'CLOUD'},
    });
    expect(appdata.settings['color'], 'CLOUD', reason: '开关关闭时应与云端一致（零回归 ✓）');
  });

  test('T-DS4：清除本设备设置 ⇒ 只关开关、值全部保留 ✓', () {
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings['color'] = 'LOCAL';

    appdata.settings.resetDeviceSpecificSettings();

    expect(
      appdata.settings.isAppearanceDeviceSettingsEnabled(),
      isFalse,
      reason: '清除按钮的新语义 = 关闭开关（这些键重新参与同步 ✓）',
    );
    expect(
      appdata.settings['color'],
      'LOCAL',
      reason: '清除按钮**不得**清值（用户方案：不丢数据 ✓；旧版会清成默认 ✗）',
    );
  });
}
