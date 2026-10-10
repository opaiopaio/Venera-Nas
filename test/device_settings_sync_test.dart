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
    // ⚠️ 2026-10-10（回归审查 P0-2 ✓）：**不再**在这里硬塞 `disableSyncFields` ✗ ——
    // 原先靠它非空才让 `saveData` 产出 `syncdata.json` ✗ ⇒ 默认配置下是**假绿** ✓
    //（真实上行那时会退回**原始 `appdata.json`** ✗，标志与 deviceId 全部进云端 ✓）。
    // 现在 `saveData` **始终**产出过滤后的 `syncdata.json` ✓（P0-1 ✓）⇒ 保持**默认空串** ✓ = 真实默认路径 ✓。
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

    // ⭐ P0-1（回归审查 ✓）：**默认配置**（`disableSyncFields` 为空串 ✓）下也必须如此 ✓ ——
    // 并且 `deviceId` / 旧 `deviceSpecificSettings` 容器也**不得**进快照 ✓（旧版正是从这里泄漏 ✓）。
    expect(
      snap.containsKey('deviceId'),
      isFalse,
      reason: '上行快照不得包含 deviceId ✓（它会让对端把本机 id 写进自己的存档 ✗）',
    );
    expect(
      snap.containsKey('deviceSpecificSettings'),
      isFalse,
      reason: '上行快照不得包含旧设备层容器 ✓',
    );
    final raw =
        jsonDecode(File('${tempDir.path}/syncdata.json').readAsStringSync())
            as Map;
    expect(raw.containsKey('deviceId'), isFalse, reason: '顶层也不得出现 deviceId ✓');
    expect(
      raw.containsKey('deviceSpecificSettings'),
      isFalse,
      reason: '顶层也不得出现 deviceSpecificSettings ✓',
    );
    expect(
      (appdata.settings['disableSyncFields'] as String).isEmpty,
      isTrue,
      reason: '本用例必须跑在**默认配置**下 ✓（否则就是 P0-2 那种假绿 ✗）',
    );
  });

  test('T-SY2 入方向 · 本机开关 OFF：应用快照（含背景色 ✓），但**不应用背景图片**', () async {
    appdata.settings.setEnabledAppearanceDeviceSettings(true);
    appdata.settings.setEnabledDeviceSpecificSettings(true);
    appdata.settings['backgroundImage'] = 'bg1.png';
    appdata.settings['backgroundColor'] = '#112233';
    appdata.settings['backgroundImageOpacity'] = 0.5;
    appdata.settings['backgroundImageFit'] = 'cover';
    appdata.settings['backgroundImageSource'] = '/peer/old.png';
    appdata.settings['color'] = 'RED';
    appdata.settings['readerMode'] = 'page';
    final snap = await uploadSnapshot();

    // 切到"设备2"：开关全关 ✓、值都是它自己的 ✓
    appdata.settings.setEnabledAppearanceDeviceSettings(false);
    appdata.settings.setEnabledDeviceSpecificSettings(false);
    appdata.settings['backgroundImage'] = 'bg2.png';
    appdata.settings['backgroundColor'] = 'transparent';
    appdata.settings['backgroundImageOpacity'] = 1.0;
    appdata.settings['backgroundImageFit'] = 'fill';
    appdata.settings['backgroundImageSource'] = '/mine/new.png';
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
    // ⭐ P1-6（回归审查 ✓）：`f972730` 修的是**三个键** ⇒ 透明度与 fit 也必须能应用 ✓
    expect(
      appdata.settings['backgroundImageOpacity'],
      0.5,
      reason: '背景透明度属于"值" ⇒ 本机开关关时必须能恢复 ✓',
    );
    expect(
      appdata.settings['backgroundImageFit'],
      'cover',
      reason: '背景适配方式属于"值" ⇒ 本机开关关时必须能恢复 ✓',
    );
    // 规则 4（背景图片永不应用 ✓）
    expect(
      appdata.settings['backgroundImage'],
      'bg2.png',
      reason: '背景图片文件名**任何情况下都不应用** ✗（图文件不随同步传输 ⇒ 应用了会指向不存在的图 ✓）',
    );
    // ⭐ P1-6（回归审查 ✓）：本机选取路径同理**永不应用** ✗ ——
    // 否则设置页会显示对端的路径 ✓，与"图片不应用"不自洽 ✗。
    expect(
      appdata.settings['backgroundImageSource'],
      '/mine/new.png',
      reason:
          'backgroundImageSource 是**本机**选取路径 ⇒ 必须与 backgroundImage 一起永不应用 ✓',
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

  test('T-SY5 上行路径静态锁：恒用过滤后的 syncdata.json，且只剔三类，绝不剔设置值', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    // ⭐ P0-2（回归审查 ✓）：原先本用例静态扫的是 `_backupLocalData`（**下载回滚副本** ✗，
    // 不是上行路径 ✗，注释也写错了 ✓）⇒ 假绿 ✓。现在锁**真正的上行分支** ✓：
    // `data_sync.dart` 的 WebDAV 上传必须**恒**用 `exportAppData(true)` ✓（= 打包 `syncdata.json` ✓）。
    final sync = codeOf('lib/utils/data_sync.dart');
    expect(
      sync.contains('exportAppData(true)'),
      isTrue,
      reason:
          '上行必须恒用 exportAppData(true) ✓ ⇒ 打包过滤后的 syncdata.json ✓'
          '（旧版默认走 exportAppData(false) ⇒ 原始 appdata.json 含 deviceId 与两个标志 ✗）',
    );
    expect(
      RegExp(r'exportAppData\(\s*[^)]*disableFields').hasMatch(sync),
      isFalse,
      reason: '上行不得再按用户是否自定义剔除清单来二选一 ✗（默认空串会漏原始文件 ✓）',
    );

    // 剔除规则本体在 `appdata.dart` 的 `saveData` ✓（生成 syncdata.json 的唯一入口 ✓）。
    final appdataSrc = codeOf('lib/foundation/appdata.dart');
    for (final flag in const <String>[
      'deviceSpecificAppearanceEnabled',
      'deviceSpecificReaderEnabled',
    ]) {
      expect(
        appdataSrc.contains(flag),
        isTrue,
        reason: 'syncdata 必须剔除开关标志 `$flag` ✗（否则对端会被自动打开 ✓）',
      );
    }
    for (final keep in const <String>[
      'backgroundColor',
      'backgroundImage',
      'backgroundImageOpacity',
      'backgroundImageFit',
      'backgroundImageSource',
    ]) {
      expect(
        appdataSrc.contains('remove("$keep")'),
        isFalse,
        reason:
            'syncdata **不得**剔除 `$keep` ✓（出方向永远完整快照 ✓；'
            '这些键的"不参与/不应用"只发生在**入方向** ✓）',
      );
    }
  });

  test('T-SY6 迁移：多历史条目时以当前条目为权威（P1-5）', () async {
    // 孤儿条目（开关 ON + 过期背景图）+ 当前条目（开关 OFF）
    appdata.settings['deviceId'] = 'current-device';
    appdata.settings['backgroundImage'] = 'kept.png';
    appdata.settings['deviceSpecificSettings'] = <String, dynamic>{
      'old-orphan': <String, dynamic>{
        'enabledAppearance': true,
        'backgroundImage': 'stale.png',
      },
      'current-device': <String, dynamic>{'enabledAppearance': false},
    };
    await appdata.saveData(false);

    await appdata.doInit();

    expect(
      appdata.settings.isAppearanceDeviceSettingsEnabled(),
      isFalse,
      reason: '权威条目（当前 deviceId）开关是 false ⇒ 不得被孤儿条目**静默打开** ✗',
    );
    expect(
      appdata.settings['backgroundImage'],
      'kept.png',
      reason: '当前条开关关着 ⇒ 主表当前值胜出 ✓（不得被孤儿过期值覆盖 ✗）',
    );
  });
}
