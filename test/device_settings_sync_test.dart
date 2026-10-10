import 'dart:convert';
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

/// ⭐ 两台设备 × 云同步/备份的**语义守护**（2026-10-10 用户要求 ✓）。
///
/// 用户原话 ✓：「修改启用此设备特定设置后，**webdav 云同步会同步这个按钮的设置配置** ✗，
/// 也就是说，如果我**设备 1 的该设置启动，那设备 2 通过云同步也就把他的设置自动打开了** ✗」
///
/// 用户给的规则 ✓：
/// 1. **出方向永远生成完整快照** ✓（所有页面的设置值都包含 ✓，不受本机开关影响 ✗）；
/// 2. **两个开关标志永远只属于本机** ✗（不上传 ✓、不在入方向被应用 ✓）；
/// 3. **入方向**按**本机开关**决定是否应用 ✓（本机 OFF ⇒ 应用 ✓；本机 ON ⇒ 跳过 ✓）；
/// 4. **例外**：`backgroundImage`（文件名 ✓）**任何情况下都不应用** ✗（图文件不随传输 ✓）；
///    但 `backgroundColor`（背景色 ✓）要**正常应用** ✓。
///
/// 做法 ✓：用**同一进程 + JSON 快照**模拟两台设备 ✓（设备1 的值打包成快照 ⇒ 换成设备2 的本机状态 ⇒ 再应用 ✓）。
/// 快照来源 = `saveData()` 生成的 `syncdata.json` ✓（`appdata.dart` 的出方向产物 ✓，
/// 与 `utils/data_sync.dart` 上传的 `appdata.json` 走同一套剔除规则 ✓，后者由 T-SY5 静态锁定 ✓）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-sync-');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    // ⚠️ `App.dataPath` 是 `late` 字段 ✓（未初始化时读会抛 ✗）⇒ 直接赋值 ✓（与既有测试同做法 ✓）。
    App.dataPath = tempDir.path;
    await appdata.init();
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = '';
    appdata.settings['backgroundColor'] = 'transparent';
    appdata.settings['color'] = 'system';
    appdata.settings['readerMode'] = 'scroll';
    // 让 `saveData()` 真的产出 `syncdata.json` ✓（该文件只在用户自定义过剔除清单时才生成 ✓）。
    appdata.settings['disableSyncFields'] = 'noSuchKeyForTest';
  });

  tearDown(() {
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = '';
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 出方向：跑一次真实 `saveData()` 并读回 `syncdata.json` 的 `settings` ✓。
  Future<Map<String, dynamic>> uploadSnapshot() async {
    await appdata.saveData(false);
    final f = File('${tempDir.path}/syncdata.json');
    expect(f.existsSync(), isTrue, reason: '出方向应产出同步快照 ✓');
    final json = jsonDecode(f.readAsStringSync()) as Map;
    return Map<String, dynamic>.from(json['settings'] as Map);
  }

  test('T-SY1 出方向：开关 ON 时快照仍含所有设置值，但**不含**开关标志', () async {
    // 设备1：开关 ON，并改了几个"设备专属"的值 ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    appdata.settings['backgroundImage'] = 'bg1.png';
    appdata.settings['backgroundColor'] = '#112233';
    appdata.settings['color'] = 'RED';
    appdata.settings['readerMode'] = 'page';

    final snap = await uploadSnapshot();

    // 规则 1 ✓：值**全都**在快照里（含背景图片文件名与背景色 ✓）。
    expect(
      snap['backgroundImage'],
      'bg1.png',
      reason: '出方向必须是完整快照 ⇒ 值不能被开关过滤 ✗',
    );
    expect(snap['backgroundColor'], '#112233');
    expect(snap['color'], 'RED');
    expect(snap['readerMode'], 'page');

    // 规则 2 ✓：两个开关标志**永不上传** ✗（这正是用户报的"开关被同步过去" ✓）。
    expect(
      snap.containsKey('deviceSpecificAppearanceEnabled'),
      isFalse,
      reason: '开关标志被上传 ⇒ 设备2 同步后会被自动打开（用户实测反馈 ✗）',
    );
    expect(snap.containsKey('deviceSpecificReaderEnabled'), isFalse);
  });

  test('T-SY2 入方向 · 本机开关 OFF：应用快照（含背景色 ✓），但**不应用背景图片**', () async {
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    appdata.settings['backgroundImage'] = 'bg1.png';
    appdata.settings['backgroundColor'] = '#112233';
    appdata.settings['color'] = 'RED';
    appdata.settings['readerMode'] = 'page';
    final snap = await uploadSnapshot();

    // 切到"设备2"：开关全关 ✓、值都是它自己的 ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = 'bg2.png';
    appdata.settings['backgroundColor'] = 'transparent';
    appdata.settings['color'] = 'system';
    appdata.settings['readerMode'] = 'scroll';

    appdata.syncData(<String, dynamic>{'settings': snap});

    // 规则 3（本机 OFF ⇒ 应用 ✓）
    expect(appdata.settings['color'], 'RED', reason: '本机开关关 ⇒ 应接受同步来的外观配置 ✓');
    expect(appdata.settings['readerMode'], 'page', reason: '阅读开关同理 ✓');
    expect(
      appdata.settings['backgroundColor'],
      '#112233',
      reason: '用户明确要求：**背景色要正常应用** ✓（旧版把它列进禁用清单 ⇒ 永远恢复不了 ✗）',
    );
    // 规则 4（背景图片永不应用 ✓）
    expect(
      appdata.settings['backgroundImage'],
      'bg2.png',
      reason: '背景图片文件名**任何情况下都不应用** ✗（图文件不随同步传输 ⇒ 应用了会指向不存在的图 ✓）',
    );
  });

  test('T-SY3 入方向 · 本机开关 ON：跳过、一切保持不变', () async {
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    appdata.settings['backgroundImage'] = 'bg1.png';
    appdata.settings['backgroundColor'] = '#112233';
    appdata.settings['color'] = 'RED';
    appdata.settings['readerMode'] = 'page';
    final snap = await uploadSnapshot();

    // "设备2"：开关 ON，值都是本机自己的 ✓
    appdata.settings['backgroundImage'] = 'bg2.png';
    appdata.settings['backgroundColor'] = '#445566';
    appdata.settings['color'] = 'BLUE';
    appdata.settings['readerMode'] = 'scroll';

    appdata.syncData(<String, dynamic>{'settings': snap});

    expect(appdata.settings['color'], 'BLUE', reason: '本机开关 ON ⇒ 不覆盖 ✓');
    expect(appdata.settings['readerMode'], 'scroll', reason: '本机开关 ON ⇒ 不覆盖 ✓');
    expect(
      appdata.settings['backgroundColor'],
      '#445566',
      reason: '本机开关 ON ⇒ 不覆盖 ✓',
    );
    expect(appdata.settings['backgroundImage'], 'bg2.png');
  });

  test('T-SY4 开关标志在"上传 → 下载"往返后不变（本次 bug 的直接断言）', () async {
    // 设备1：外观开关 ON、阅读开关 OFF
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    final snap = await uploadSnapshot();

    // 设备2：两个开关都 OFF ⇒ 应用快照后**必须仍是 OFF** ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.syncData(<String, dynamic>{'settings': snap});
    expect(
      appdata.settings.isAppearanceDeviceSettingsEnabled(),
      isFalse,
      reason: '设备1 的开关状态被同步过来 ⇒ 设备2 的开关被自动打开（用户实测反馈 ✗）',
    );
    expect(appdata.settings.isDeviceSpecificSettingsEnabled(), isFalse);

    // 反向：设备2 打开开关 ⇒ 应用同一份快照后**必须仍是 ON** ✓（本机选择不被对端改 ✗）
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.syncData(<String, dynamic>{'settings': snap});
    expect(appdata.settings.isAppearanceDeviceSettingsEnabled(), isTrue);
  });

  test('T-SY5 上传侧剔除规则：只剔开关标志与设备 id，绝不剔设置值', () {
    final src = File('lib/utils/data_sync.dart').readAsStringSync();
    final code = src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    for (final flag in const <String>[
      'deviceSpecificAppearanceEnabled',
      'deviceSpecificReaderEnabled',
    ]) {
      expect(
        code.contains("'$flag'"),
        isTrue,
        reason: '上行快照必须剔除开关标志 `$flag` ✗（否则对端会被自动打开 ✓）',
      );
    }
    for (final keep in const <String>['backgroundColor', 'backgroundImage']) {
      expect(
        code.contains("remove('$keep')"),
        isFalse,
        reason: '上行快照**不得**剔除设置值 `$keep` ✓（用户要求永远生成完整快照 ✓）',
      );
    }
  });
}
