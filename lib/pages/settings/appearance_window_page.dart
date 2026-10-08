part of 'settings_page.dart';

/// ⭐ N1：外观 →「Window & controls」**独立子页** ✓（用户规格：除「主题」「漫画显示」外全部子页化 ✓）。
///
/// 由 appearance.dart **原样搬迁** ✓（脚本搬移 ✓，设置项与其 key **完全不变** ✓）；
/// 布局沿用 CustomScrollView + 各行 .toSliver() ✓（与搬迁前逐行一致 ✓，
/// 并满足 mask_entry_test 的遮罩规范 ✓）。
class AppearanceWindowPage extends StatelessWidget {
  const AppearanceWindowPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖 ✓：开关/设置变化后本页即时刷新 ✓（禁止 forceRebuild 整树遍历 ✗）
    AppSettingsScope.of(context);
    return PopUpWidgetScaffold(
      title: "Window & controls".tl,
      body: CustomScrollView(
        slivers: [
          // ⭐ N1：本页总开关 ✓（用户规格：每个子页一个「是否跟随系统主题设置」✓，默认**开** ✓）。
          // 开 = 本页所有自定义项**不参与渲染** ✓（回到最初干净默认 ✓）；关 = 才启用下面的自定义 ✓。
          _SwitchSetting(
            title: "Follow system theme".tl,
            subtitle: "On: use the default look; Off: customize below".tl,
            settingKey: "windowOverlayFollowTheme",
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
          // ⭐ N1：总开关开启（跟随系统主题 ✓）时 → **隐藏**本页所有自定义项 ✓（只留标题与开关 ✓）。
          // 用 Dart 列表的条件展开 ✓，不移动既有代码 ✓（设置项与 key 一律不变 ✓）。
          if (appdata.settings['windowOverlayFollowTheme'] != true) ...[
            ColorSettingTile(
              // H3 改名 ✓：原来叫「窗口/按钮背景颜色」✗ —— 现在按钮有**独立**设置了 ✓，
              // 这一项只管**窗口**（面板/卡片/设置行/侧栏/顶栏 ✓），名实相符 ✓。
              title: "Window background color".tl,
              settingValue: (appdata.settings['windowOverlayColor'] ?? 'system')
                  .toString(),
              allowSystem: true,
              allowTransparent: true,
              onPicked: (value) async {
                appdata.settings['windowOverlayColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              // H3 改名 ✓（同上，只管窗口 ✓）
              title: "Window background opacity".tl,
              settingsIndex: "windowOverlayOpacity",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ H3：**按钮背景**独立控制 ✓ —— 与窗口分离后，胶囊按钮不再和面板同色融合 ✓。
            // 颜色默认「跟随窗口」✓（`system` ✓）；不透明度默认 0.85 ✓（窗口默认 1.0 → 有层次 ✓）。
            ColorSettingTile(
              title: "Button background color".tl,
              settingValue: (appdata.settings['buttonOverlayColor'] ?? 'system')
                  .toString(),
              allowSystem: true,
              allowTransparent: true,
              onPicked: (value) async {
                appdata.settings['buttonOverlayColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Button background opacity".tl,
              settingsIndex: "buttonOverlayOpacity",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ J1：**图标按钮**（只有图标的按钮 ✓：顶栏动作按钮 / `IconButton` / 页面右上「⋯」✓）
            // 独立控制 ✓ —— 颜色默认「跟随胶囊按钮」✓、不透明度默认 0.85 ✓（与胶囊一致 ✓ → 零视觉变化 ✓）。
            ColorSettingTile(
              title: "Icon button background color".tl,
              settingValue: (appdata.settings['iconOverlayColor'] ?? 'system')
                  .toString(),
              allowSystem: true,
              allowTransparent: true,
              onPicked: (value) async {
                appdata.settings['iconOverlayColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Icon button background opacity".tl,
              settingsIndex: "iconOverlayOpacity",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ K1：**标签背景**独立控制 ✓（颜色 + 不透明度，与按钮遮罩同形态 ✓）。
            // ⚠️ 与上方「标签颜色」开关的关系 ✓：模式 = **跟随主题** 时用 `secondaryContainer` ✓（此项不生效 ✓）；
            // 模式 = **跟随遮罩**（默认 ✓）时用本项 ✓。颜色默认 `system` = 跟随窗口色 ✓（颜色零回归 ✓）。
            ColorSettingTile(
              title: "Tag background color".tl,
              settingValue: (appdata.settings['tagOverlayColor'] ?? 'system')
                  .toString(),
              allowSystem: true,
              allowTransparent: true,
              onPicked: (value) async {
                appdata.settings['tagOverlayColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Tag background opacity".tl,
              settingsIndex: "tagOverlayOpacity",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ AF1（用户要求 ✓）：**顶栏「漫画源」按钮**（分类/发现页顶部那一排 ✓ + 「+ 加号」✓）
            // 独立可控 ✓ —— 颜色（跟随系统=跟主题 / 透明 / 自定义 ✓）+ 不透明度 ✓。
            // 取值入口：`foundation/window_overlay.dart` 的 `sourceTabOverlayColor()` ✓；
            // 应用点：`components/appbar.dart` 的 chip 填色与「+ 加号」填色 ✓。
            // ⭐ AG1（用户要求 ✓）：**去掉组标题行** ✗（用户："这个删掉" ✓），
            // 颜色项改名为「**发现/分类页漫画源颜色**」✓。
            ColorSettingTile(
              title: "Source color on Discover and Categories".tl,
              settingValue:
                  (appdata.settings['sourceTabOverlayColor'] ?? 'system')
                      .toString(),
              allowSystem: true,
              allowTransparent: true,
              onPicked: (value) async {
                appdata.settings['sourceTabOverlayColor'] = value;
                await appdata.saveData();
                App.forceRebuild();
              },
            ).toSliver(),
            _SliderSetting(
              title: "Source buttons opacity".tl,
              settingsIndex: "sourceTabOverlayOpacity",
              interval: 0.05,
              min: 0.0,
              max: 1.0,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Corner style".tl,
              settingKey: "windowOverlayCorner",
              optionTranslation: {
                "rounded": "Rounded".tl,
                "square": "Square".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
          ], // ← N1：跟随主题时隐藏到此结束 ✓
        ],
      ),
    );
  }
}
