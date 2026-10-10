part of 'settings_page.dart';

/// ⭐ N1：外观 →「Text」**独立子页** ✓（用户规格：除「主题」「漫画显示」外全部子页化 ✓）。
///
/// 由 appearance.dart **原样搬迁** ✓（脚本搬移 ✓，设置项与其 key **完全不变** ✓）；
/// 布局沿用 CustomScrollView + 各行 .toSliver() ✓（与搬迁前逐行一致 ✓，
/// 并满足 mask_entry_test 的遮罩规范 ✓）。
class AppearanceTextPage extends StatelessWidget {
  const AppearanceTextPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖 ✓：开关/设置变化后本页即时刷新 ✓（禁止 forceRebuild 整树遍历 ✗）
    AppSettingsScope.of(context);

    // ⭐ 2026-10-10（用户要求 ✓）：**按设备独立保存本页设置** ✓ —— 与「阅读」页同一套机制 ✓：
    // 启用后本设备改的值只写在本设备 ✓，同步来的配置不会覆盖它 ✓。
    final useDeviceSpecificSettings = appdata.settings
        .isAppearanceDeviceSettingsEnabled();
    return PopUpWidgetScaffold(
      // ⭐ 批次 4a（2026-10-09 用户指示 ✓）：本页是**二级页面** ✓，补 `popupStyle: true` ⇒ 表面走切片+色调 ⇒ 跟随自定义 ✓。
      // ⚠️ 推送方式**暂不改** ✗：`showPopUpWidget` 走 `rootNavigator: true`（`pop_up_widget.dart:128-131` ✓），
      // 其 barrier 会盖住左侧设置栏 ⇒ 会**回退 AO1**（`appearance.dart:134-137` ✓ 已修 ✓）⇒ 需用户裁定后另做 ✓。
      popupStyle: true,
      title: "Text".tl,
      body: CustomScrollView(
        slivers: [
          // ⭐ N1：文字页总开关 ✓（默认开 = 主题字体/颜色/字号 ✓；关才启用下面各项 ✓）
          _SwitchSetting(
            title: "Follow system theme".tl,
            subtitle: "On: use the default look; Off: customize below".tl,
            settingKey: "textFollowTheme",
            useDeviceSettings: useDeviceSpecificSettings,
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
          // ⭐ N1：跟随系统主题（默认）时隐藏本节自定义项 ✓
          if (appdata.settings['textFollowTheme'] != true) ...[
            // ⭐ 本轮（用户实测反馈 ✓）：按「不同内容控制」分组 ✓ ——
            // ① 字体颜色 + 字体 + 自定义字体文件 + 字号缩放 ✓；② 文字阴影（开关 + 颜色 + 模糊 + 两轴偏移 ✓）；
            // ③ 文字发光（开关 + 颜色 + 半径 + 强度 ✓）；④ 末尾的「重置」单独成组 ✓。
            // 组与组之间加**分割线** ✓ —— 沿用 `reader.dart` 既有的 sliver 分割线写法 ✓
            //（`SliverToBoxAdapter` + `Divider` ✓）；高度取令牌 ✓ 且与 Flutter `Divider`
            // 默认一致 ✓ ⇒ 不改变原有行距观感 ✓。
            const SliverToBoxAdapter(child: Divider(height: AppSpace.lg)),
            ColorSettingTile(
              title: "Text color".tl,
              settingValue: (appdata.settings['globalTextColor'] ?? 'system')
                  .toString(),
              allowSystem: true,
              onPicked: (value) async {
                appdata.settings['globalTextColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            SelectSetting(
              title: "Font".tl,
              settingKey: "globalFontFamily",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "system": "Follow system".tl,
                "Microsoft YaHei": "微软雅黑",
                "SimHei": "黑体",
                "SimSun": "宋体",
                "Noto Sans CJK SC": "Noto Sans CJK SC",
                "Source Han Sans SC": "思源黑体",
                "PingFang SC": "苹方",
                "WenQuanYi Micro Hei": "文泉驿微米黑",
                "serif": "Serif",
                "monospace": "Monospace",
              },
              onChanged: () async {
                await App.init();
                App.forceRebuild();
              },
            ).toSliver(),
            const _FontFileTile().toSliver(),
            _SliderSetting(
              title: "Font scale".tl,
              settingsIndex: "globalFontScale",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.05,
              min: 0.8,
              max: 1.4,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ 组间分割线 ✓（本轮用户要求 ✓）：字体组 → 文字阴影组 ✓。
            const SliverToBoxAdapter(child: Divider(height: AppSpace.lg)),
            _SwitchSetting(
              title: "Text shadow".tl,
              settingKey: "textShadowEnabled",
              useDeviceSettings: useDeviceSpecificSettings,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            ColorSettingTile(
              title: "Shadow color".tl,
              settingValue: (appdata.settings['textShadowColor'] ?? '#000000')
                  .toString(),
              onPicked: (value) async {
                appdata.settings['textShadowColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Shadow blur".tl,
              settingsIndex: "textShadowBlur",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.5,
              min: 0.0,
              max: 10.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Shadow offset X".tl,
              settingsIndex: "textShadowOffsetX",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.5,
              min: -4.0,
              max: 4.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Shadow offset Y".tl,
              settingsIndex: "textShadowOffsetY",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.5,
              min: -4.0,
              max: 4.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ 组间分割线 ✓（本轮用户要求 ✓）：文字阴影组 → 文字发光组 ✓。
            const SliverToBoxAdapter(child: Divider(height: AppSpace.lg)),
            _SwitchSetting(
              title: "Text glow".tl,
              settingKey: "textGlowEnabled",
              useDeviceSettings: useDeviceSpecificSettings,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            ColorSettingTile(
              title: "Glow color".tl,
              settingValue: (appdata.settings['textGlowColor'] ?? '#FFFFFF')
                  .toString(),
              onPicked: (value) async {
                appdata.settings['textGlowColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Glow radius".tl,
              settingsIndex: "textGlowRadius",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 1.0,
              min: 0.0,
              max: 20.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Glow strength".tl,
              settingsIndex: "textGlowStrength",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ 组间分割线 ✓（本轮用户要求 ✓）：文字发光组 → 末尾「重置」行 ✓。
            const SliverToBoxAdapter(child: Divider(height: AppSpace.lg)),
            ListTile(
              title: Text("Reset".tl),
              trailing: const Icon(Icons.restart_alt),
              onTap: () async {
                appdata.settings['globalTextColor'] = 'system';
                appdata.settings['globalFontFamily'] = 'system';
                appdata.settings['globalFontFile'] = '';
                appdata.settings['globalFontSource'] = '';
                appdata.settings['globalFontScale'] = 1.0;
                appdata.settings['textShadowEnabled'] = false;
                appdata.settings['textGlowEnabled'] = false;
                await appdata.saveData();
                await loadCustomFont();
                App.forceRebuild();
              },
            ).toSliver(),
          ], // ← N1：文字自定义项隐藏到此结束 ✓
        ],
      ),
    );
  }
}
