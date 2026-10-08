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
    return PopUpWidgetScaffold(
      title: "Text".tl,
      body: CustomScrollView(
        slivers: [
          // ⭐ N1：文字页总开关 ✓（默认开 = 主题字体/颜色/字号 ✓；关才启用下面各项 ✓）
          _SwitchSetting(
            title: "Follow system theme".tl,
            subtitle: "On: use the default look; Off: customize below".tl,
            settingKey: "textFollowTheme",
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
          // ⭐ N1：跟随系统主题（默认）时隐藏本节自定义项 ✓
          if (appdata.settings['textFollowTheme'] != true) ...[
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
              interval: 0.05,
              min: 0.8,
              max: 1.4,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SwitchSetting(
              title: "Text shadow".tl,
              settingKey: "textShadowEnabled",
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
              interval: 0.5,
              min: 0.0,
              max: 10.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Shadow offset X".tl,
              settingsIndex: "textShadowOffsetX",
              interval: 0.5,
              min: -4.0,
              max: 4.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Shadow offset Y".tl,
              settingsIndex: "textShadowOffsetY",
              interval: 0.5,
              min: -4.0,
              max: 4.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SwitchSetting(
              title: "Text glow".tl,
              settingKey: "textGlowEnabled",
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
              interval: 1.0,
              min: 0.0,
              max: 20.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Glow strength".tl,
              settingsIndex: "textGlowStrength",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
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
