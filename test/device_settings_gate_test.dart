import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// ⭐ 设备特定设置的**门控行为测试**（2026-10-10 草稿回顾发现缺失 ⇒ 补上 ✓）
///
/// 背景 ✓：外观页 / 阅读页各有「启用此设备特定设置」开关 ✓，机制是
/// `_data['deviceSpecificSettings'][deviceId][key]` 三级优先（漫画 → 设备 → 全局 ✓）。
/// 三组归属 ✓：**外观键**看外观开关 ✓、**阅读键**看阅读开关 ✓、**其余键一律不受影响** ✓。
///
/// 本测试锁定三件最容易回归的事 ✓：
/// ① 归属划分正确 ✓（外观 / 阅读 / 其余 ✓）；
/// ② **开关关闭时写入不落设备表** ✓（= 零回归 ✓，与改造前行为一致 ✓）；
/// ③ **清除按钮真的清空本设备专属设置** ✓。
///
/// 说明 ✓：`appdata.settings` 在构造时即填充默认值 ✓，无需 path_provider 脚手架 ✓
///（同 `appearance_behavior_test.dart` 的做法 ✓）；`setUp`/`tearDown` 负责复位 ✓。
void main() {
  // 会改动的键与开关（测试前后复位）
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

  setUp(() {
    for (final k in touchedKeys) {
      original[k] = appdata.settings[k];
    }
    origAppearanceGate = appdata.settings.isAppearanceDeviceSettingsEnabled();
    origReaderGate = appdata.settings.isDeviceSpecificSettingsEnabled();
    // 从干净状态开始：两个开关都关、设备表清空 ✓
    appdata.settings.resetDeviceSpecificSettings();
  });

  tearDown(() {
    appdata.settings.setEnabledAppearanceDeviceSettings(origAppearanceGate);
    appdata.settings.setEnabledDeviceSpecificSettings(origReaderGate);
    appdata.settings.resetDeviceSpecificSettings();
    for (final k in touchedKeys) {
      appdata.settings[k] = original[k];
    }
  });

  test('T-DS1：三组归属划分正确（外观 / 阅读 / 其余）', () {
    // 开关全关时：任何键都不受保护 ✓（= 改造前行为 ✓）
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    expect(appdata.settings.isDeviceProtected('color'), isFalse);
    expect(appdata.settings.isDeviceProtected('readerMode'), isFalse);

    // 只开「外观」开关 ⇒ 只有外观键受保护 ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    expect(
      appdata.settings.isDeviceProtected('color'),
      isTrue,
      reason: '外观键应归外观开关',
    );
    expect(appdata.settings.isDeviceProtected('globalIconColor'), isTrue);
    expect(appdata.settings.isDeviceProtected('theme_mode'), isTrue);
    expect(
      appdata.settings.isDeviceProtected('readerMode'),
      isFalse,
      reason: '阅读键不该被外观开关管',
    );

    // 只开「阅读」开关 ⇒ 只有阅读键受保护 ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    expect(appdata.settings.isDeviceProtected('readerMode'), isTrue);
    expect(appdata.settings.isDeviceProtected('customImageProcessing'), isTrue);
    expect(
      appdata.settings.isDeviceProtected('color'),
      isFalse,
      reason: '外观键不该被阅读开关管',
    );

    // 其余键：无论开哪个都不受保护 ✓（发现 / 本地收藏 / 应用 / 网络 ✓）
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

  test('T-DS2：开关开启后，受保护键写入设备层、其余键仍写全局层', () {
    // ⚠️ 探测方法说明 ✓：`getDeviceReaderSetting` 是**三级优先读取**（设备 → 回落全局 ✓），
    // 而 `syncData` 对 `color`/`language` 本就有额外过滤（见 `_disableSync` ✓）⇒ 不能用"同步是否覆盖"探测 ✗。
    // 改用**确定性探针** ✓：调 `resetDeviceSpecificSettings()` 清掉设备层 ✓，看值是否回落 ✓。
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);

    // ① 先造一个"全局层"的值 ✓（关掉开关时写入的就是全局层 ✓）
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['color'] = 'GLOBAL';
    appdata.settings.setEnabledAppearanceDeviceSettings(true);

    // ② 受保护键：开开关后写入 ⇒ 落在**设备层** ✓
    appdata.settings['color'] = 'DEVICE';
    expect(appdata.settings['color'], 'DEVICE', reason: '开启后本设备值应优先');

    // ③ 其余键：无论开关如何 ⇒ 始终写**全局层** ✓
    appdata.settings['historyRetentionDays'] = 7;

    // ④ 清掉设备层 ⇒ 受保护键"回落全局"、其余键不受影响 ✓ ⇒ 反证两者所在层不同 ✓
    appdata.settings.resetDeviceSpecificSettings();

    expect(
      appdata.settings['color'],
      'GLOBAL',
      reason: '清除设备层后外观键应回落到全局值（证明它原本在设备层）',
    );
    expect(
      appdata.settings['historyRetentionDays'],
      7,
      reason: '其余键应在全局层，清除设备层不该影响它',
    );
  });

  test('T-DS3：开关关闭时写入直接进全局层（零回归，与改造前一致）', () {
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);

    appdata.settings['color'] = 'GLOBAL_ONLY';
    appdata.settings['readerMode'] = 'GLOBAL_MODE';

    // 清设备层 ⇒ 值仍在 ⇒ 证明它们**没有**进设备层 ✓（与改造前行为一致 ✓）
    appdata.settings.resetDeviceSpecificSettings();

    expect(
      appdata.settings['color'],
      'GLOBAL_ONLY',
      reason: '开关关闭时写入应直接进全局层（零回归）',
    );
    expect(
      appdata.settings['readerMode'],
      'GLOBAL_MODE',
      reason: '开关关闭时写入应直接进全局层（零回归）',
    );
  });

  test('T-DS4：清除后本设备专属值消失、回落到全局值', () {
    // 先造一个"全局值" ✓（关掉开关时写入的就是全局 ✓）
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['color'] = 'GLOBAL';
    // 再开开关写一个"本设备值" ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings['color'] = 'DEVICE';

    expect(appdata.settings['color'], 'DEVICE', reason: '开启后本设备值应优先于全局值');

    appdata.settings.resetDeviceSpecificSettings();

    expect(appdata.settings['color'], 'GLOBAL', reason: '清除本设备专属设置后，应回落到全局值');
  });
}
