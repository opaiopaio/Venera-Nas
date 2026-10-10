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

/// ⭐ 用户视角不变量守护（2026-10-10 ✓，用户方案重构后 ✓）。
///
/// 用户四步实测（**重构前** ✗）：① 关开关设背景 ⇒ 正常 ✓；② 开开关 ⇒ 立刻变白 ✗；
/// ③ 重启 ⇒ 恢复 ✓；④ 关开关 ⇒ **又变白** ✗。
/// 根因 ✓：开关让受保护键改读写**第二层** ✗ ⇒ 两套值 ⇒ 空值遮真值 / 关开关读到空 ✗ …
/// **用户方案** ✓："保持现在的设置，但阻隔同步和备份" ⇒ 只有一套值 ✓、开关是纯标志 ✓
/// ⇒ 翻转开关不改变任何读写语义 ✓ ⇒ **背景不可能因为切开关而丢** ✓。
///
/// 本文件锁四件事 ✓：
/// - **T-DS1 四步实测**：关开关设背景 → **开开关仍在** ✓ → **关开关仍在**（重构前正是这一步红 ✗）→ 重启仍在 ✓；
/// - **T-DS2 翻转开关不改值** ✓（逐键快照相等 ✓）；
/// - **T-DS3 迁移** ✓（旧第二层非空值 ⇒ 进主表 ✓；空值 ⇒ 不覆盖 ✓；重复启动幂等 ✓）。
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
    await appdata.init();
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = '';
    appdata.settings['deviceSpecificSettings'] = <String, dynamic>{};
  });

  tearDown(() {
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = '';
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> readSavedSettings() {
    final json = jsonDecode(dataFile.readAsStringSync()) as Map;
    return Map<String, dynamic>.from(json['settings'] as Map);
  }

  /// 造一张真实背景图 ✓（消费端 `currentBackgroundImageFile()` 要求文件存在 ✓）。
  void writeBackgroundImage() {
    final dir = Directory('${tempDir.path}/background')
      ..createSync(recursive: true);
    File(
      '${dir.path}/bg.png',
    ).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
  }

  test('T-DS1 用户四步：开关开/关与重启都不能让背景消失', () async {
    writeBackgroundImage();

    // ① 开关**关** ⇒ 设背景
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['backgroundImage'] = 'bg.png';
    expect(appdata.settings['backgroundImage'], 'bg.png');

    // ② 打开开关 ⇒ 必须**仍然可读**（重构前：立刻变白 ✗）
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    expect(
      appdata.settings['backgroundImage'],
      'bg.png',
      reason: '开开关不得改变读写语义 ⇒ 否则背景立刻变白（用户步骤② ✗）',
    );
    await appdata.saveData(false);

    // ③ 再关开关 ⇒ 必须**仍然可读**（重构前：这一步变白 ✗ ← 本轮重点 ✓）
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    expect(
      appdata.settings['backgroundImage'],
      'bg.png',
      reason: '关开关不得清值/读空 ⇒ 否则背景又变白（用户步骤④ ✗）',
    );

    // ④ 重启（真重读同一份存储 ✓）⇒ 仍在 ✓
    // ⚠️ 2026-10-10（回归审查 P1-6 ✓）：`doInit()` **只赋值、不清内存** ✗ ⇒ 不先破坏内存态的话
    // 这条断言**恒真** ✓（= 假绿 ✗，根本没覆盖"从文件读回" ✓）。故先清空内存值 ✓。
    appdata.settings['backgroundImage'] = '';
    expect(appdata.settings['backgroundImage'], '');
    await appdata.doInit();
    expect(
      appdata.settings['backgroundImage'],
      'bg.png',
      reason: '重启必须从 appdata.json **真的读回** ✓（先清空内存再 doInit ⇒ 不落盘就会红 ✓）',
    );
    expect(
      readSavedSettings()['backgroundImage'],
      'bg.png',
      reason: '值必须落在主表并已落盘 ✓',
    );
  });

  test('T-DS2 翻转两个开关：主表逐键不变（值一键都不许动 ✓）', () async {
    const keys = <String>[
      'backgroundImage',
      'backgroundColor',
      'theme_mode',
      'color',
      'readerMode',
      'imageFavoritesDisplayType',
    ];
    writeBackgroundImage();
    appdata.settings['backgroundImage'] = 'bg.png';

    Map<String, dynamic> snapshot() => <String, dynamic>{
      for (final k in keys) k: appdata.settings[k],
    };

    final before = snapshot();
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    expect(snapshot(), before, reason: '打开开关不得改变任何键的值 ✓');
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    expect(snapshot(), before, reason: '关闭开关不得改变任何键的值 ✓');
  });

  test('T-DS3 迁移旧存档：非空设备值进主表、空值不覆盖、且幂等', () async {
    writeBackgroundImage();
    // 构造"旧版存档" ✓：主表里 backgroundImage 为空 ✗（老用户当时只在设备层 ✓），设备层有真值 ✓，
    // 另有一个空值键（必须**不覆盖**主表已有的非空值 ✗）与一个历史 id 孤儿条目 ✓。
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings['backgroundImage'] = '';
    appdata.settings['color'] = 'KEEP';
    appdata.settings['deviceSpecificSettings'] = <String, dynamic>{
      'old-id-1': <String, dynamic>{
        'enabledAppearance': true,
        'backgroundImage': 'bg.png',
        'backgroundImageSource': '/src/bg.png',
        'color': '',
      },
    };
    await appdata.saveData(false);

    // 启动迁移 ✓
    await appdata.doInit();

    expect(
      appdata.settings['backgroundImage'],
      'bg.png',
      reason: '旧设备层的非空值必须搬进主表 ⇒ 否则老用户升级后背景消失 ✗',
    );
    expect(
      appdata.settings['backgroundImageSource'],
      '/src/bg.png',
      reason: '同组键一起迁移 ✓',
    );
    expect(
      appdata.settings['color'],
      'KEEP',
      reason: '设备层的**空值**绝不允许覆盖主表的非空值 ✓',
    );
    expect(
      appdata.settings.isAppearanceDeviceSettingsEnabled(),
      isTrue,
      reason: '旧版开关状态（enabledAppearance ✓）要迁移到新标志 ✓',
    );
    expect(
      appdata.settings['deviceSpecificSettings'],
      isEmpty,
      reason: '迁移后旧第二层被清空 ✓（不再被读取 ✓）',
    );

    // 幂等 ✓：再启动一次，值不变、也不再有可迁移内容 ✓
    final afterFirst = readSavedSettings();
    await appdata.doInit();
    expect(
      readSavedSettings()['backgroundImage'],
      afterFirst['backgroundImage'],
      reason: '重复启动必须幂等（不得反复搬运）✓',
    );
    expect(appdata.settings['backgroundImage'], 'bg.png');
  });
}
