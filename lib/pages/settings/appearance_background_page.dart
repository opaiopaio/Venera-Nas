part of 'settings_page.dart';

/// ⭐ N1：外观 →「背景」**独立子页** ✓（用户规格：除「主题」「漫画显示」外全部子页化 ✓）。
///
/// 从 `appearance.dart` **原样搬迁** ✓ —— 设置项与其 key **完全不变** ✓，仅换位置 ✓；
/// 布局改用 `CustomScrollView` + `.toSliver()` ✓，与搬迁前逐行一致 ✓，
/// 同时满足 `mask_entry_test`（设置行必须走 `.toSliver()`/`masked:`/`WindowOverlayBox` ✓）。
///
/// 备注 ✓：本页**不加**「跟随系统主题」总开关 ✓（按用户规格，背景页除外 ✓）。
class AppearanceBackgroundPage extends StatelessWidget {
  const AppearanceBackgroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖 ✓：改设置后本页即时刷新 ✓（禁止 forceRebuild 整树遍历 ✗）
    AppSettingsScope.of(context);

    // ⭐ 2026-10-10（用户要求 ✓，同日更正 ✓）：**本设置页同步总开关** ✓ —— 与「阅读」页同一套机制 ✓：
    // 打开的语义 ✓ = **本机不采用**其它设备同步/备份过来的本页设置 ✓（本页特别地：背景**图片**与字体
    // **文件**本来就不参与同步 ✓，只有背景色/透明度/填充方式等参数会 ✓）；
    // ⚠️ **不是**"值只写在本设备" ✗（旧注释写错了 ✓）—— 本机改动**仍会**随完整快照上传 ✓。
    final useDeviceSpecificSettings = appdata.settings
        .isAppearanceDeviceSettingsEnabled();
    return PopUpWidgetScaffold(
      // ⭐ 批次 4a（2026-10-09 用户指示 ✓）：本页是**二级页面** ✓，补 `popupStyle: true` ⇒ 表面走切片+色调 ⇒ 跟随自定义 ✓。
      // ⚠️ 推送方式**暂不改** ✗：`showPopUpWidget` 走 `rootNavigator: true`（`pop_up_widget.dart:128-131` ✓），
      // 其 barrier 会盖住左侧设置栏 ⇒ 会**回退 AO1**（`appearance.dart:134-137` ✓ 已修 ✓）⇒ 需用户裁定后另做 ✓。
      popupStyle: true,
      title: "Background".tl,
      body: CustomScrollView(
        slivers: [
          const _BackgroundImageTile().toSliver(),
          ColorSettingTile(
            title: "Background color".tl,
            settingValue: (appdata.settings['backgroundColor'] ?? 'transparent')
                .toString(),
            allowTransparent: true,
            onPicked: (value) async {
              appdata.settings['backgroundColor'] = value;
              await appdata.saveData();
              App.forceRebuild();
            },
          ).toSliver(),
          _SliderSetting(
            title: "Image opacity".tl,
            settingsIndex: "backgroundImageOpacity",
            useDeviceSettings: useDeviceSpecificSettings,
            interval: 0.05,
            min: 0.0,
            max: 1.0,
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
          SelectSetting(
            title: "Image fit".tl,
            settingKey: "backgroundImageFit",
            useDeviceSettings: useDeviceSpecificSettings,
            optionTranslation: {
              "cover": "Crop".tl,
              "contain": "Contain".tl,
              "fill": "Stretch".tl,
              "fitWidth": "Fit width".tl,
              "fitHeight": "Fit height".tl,
              "none": "Original size".tl,
              "scaleDown": "Scale down".tl,
              "repeat": "Tile".tl,
            },
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
        ],
      ),
    );
  }
}
