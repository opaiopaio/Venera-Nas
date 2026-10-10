part of 'settings_page.dart';

/// ⭐ N1：外观 →「Popup overlays（弹出式二级页面）」**独立子页** ✓
///（用户规格：除「主题」「漫画显示」外全部子页化 ✓；Q2 用户要求改名为"弹出式二级页面" ✓）。
///
/// 由 appearance.dart **原样搬迁** ✓（脚本搬移 ✓，设置项与其 key **完全不变** ✓）；
/// 布局沿用 CustomScrollView + 各行 .toSliver() ✓（与搬迁前逐行一致 ✓，
/// 并满足 mask_entry_test 的遮罩规范 ✓）。
class AppearanceSecondaryPage extends StatelessWidget {
  const AppearanceSecondaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖 ✓：开关/设置变化后本页即时刷新 ✓（禁止 forceRebuild 整树遍历 ✗）
    AppSettingsScope.of(context);

    // ⭐ 2026-10-10（用户要求 ✓）：**按设备独立保存本页设置** ✓ —— 与「阅读」页同一套机制 ✓：
    // 启用后本设备改的值只写在本设备 ✓，同步来的配置不会覆盖它 ✓。
    final useDeviceSpecificSettings = appdata.settings
        .isDeviceSpecificSettingsEnabled();
    return PopUpWidgetScaffold(
      // ⭐ 批次 4a（2026-10-09 用户指示 ✓）：本页是**二级页面** ✓，补 `popupStyle: true` ⇒ 表面走切片+色调 ⇒ 跟随自定义 ✓。
      // ⚠️ 推送方式**暂不改** ✗：`showPopUpWidget` 走 `rootNavigator: true`（`pop_up_widget.dart:128-131` ✓），
      // 其 barrier 会盖住左侧设置栏 ⇒ 会**回退 AO1**（`appearance.dart:134-137` ✓ 已修 ✓）⇒ 需用户裁定后另做 ✓。
      popupStyle: true,
      title: "Popup overlays".tl,
      body: CustomScrollView(
        slivers: [
          // ⭐ N1：二级页面页总开关 ✓（默认开 = 用默认弹层 ✓；关才启用样式/背景/对比强度 ✓）
          _SwitchSetting(
            title: "Follow system theme".tl,
            subtitle: "On: use the default look; Off: customize below".tl,
            settingKey: "secondaryPageFollowTheme",
            useDeviceSettings: useDeviceSpecificSettings,
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
          // ⭐ E1-①：「突出二级菜单」✓ —— 语义属于**二级页面** ✓（原先误放在「窗口与控件」区块 ✗，
          // 用户指出后归位 ✓）；开启后二级菜单/弹层点开时**周围变暗** ✓；
          // 关闭则与其它二级菜单一致（**无暗罩** ✓）；未设置时保持原有行为 ✓（零回归 ✓）。
          // 落点：`components/pop_up_widget.dart` 的 `secondaryMenuBarrierColor()` ✓
          //（另有 `showLoadingDialog` 的 `DialogRoute` 与主题层 `dialogTheme` ✓）。
          // ⭐ N1：跟随系统主题（默认）时隐藏本节自定义项 ✓
          if (appdata.settings['secondaryPageFollowTheme'] != true) ...[
            _SwitchSetting(
              title: "Highlight secondary menu".tl,
              settingKey: "secondaryMenuDim",
              useDeviceSettings: useDeviceSpecificSettings,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Secondary page style".tl,
              settingKey: "secondaryPageMode",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "opaque": "Opaque (cover)".tl,
                "transparent": "Translucent".tl,
                "off": "Off".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Secondary page background".tl,
              settingKey: "secondaryPageTint",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "darken": "Darken".tl,
                "lighten": "Lighten".tl,
                "none": "No tint".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Secondary page contrast".tl,
              settingsIndex: "secondaryPageTintStrength",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.02,
              min: 0.0,
              max: 0.6,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ AW2（用户 2026-10-09 实测 ✓）：**菜单外观三项必须回到总开关内部** ✗→✓ ——
            // 用户反馈（截图 ✓）："**弹出式二级页面总开关关闭的情况下，菜单的三个设置子项不会自动隐藏**"✗
            // —— 真因是上一轮我在"专项复查修复③"里把这三项**移出了** `secondaryPageFollowTheme` 门禁 ✗
            //（当时以为"隐藏却生效"是不一致 ✗），但**用户明确了正确语义** ✓：
            // ① 总开关 **ON**（系统主题）⇒ 三项**隐藏** ✓ 且按 `appdata` 的**默认值**生效 ✓
            //    （不透明遮挡 / 变浅 / 0.22 ✓，见 `foundation/appdata.dart` 的 AW2 注释 ✓）；
            // ② 总开关 **OFF** ⇒ 三项**显示** ✓ 并可自定义 ✓。
            // ⇒ 即"**首装即可用**、自定义项默认关闭"✓ 的既定设计 ✓，**隐藏即代表使用默认值** ✓（非缺陷 ✓）。
            SelectSetting(
              title: "Menu style".tl,
              settingKey: "menuSurfaceMode",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "opaque": "Opaque (cover)".tl,
                "transparent": "Translucent".tl,
                "off": "Off".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Menu background".tl,
              settingKey: "menuSurfaceTint",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "darken": "Darken".tl,
                "lighten": "Lighten".tl,
                "none": "No tint".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Menu contrast".tl,
              settingsIndex: "menuSurfaceTintStrength",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.02,
              min: 0.0,
              max: 0.6,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            // ⭐ 2026-10-09（用户指示 ✓）：**侧滑窗口 / 侧边栏**独立一组 ✓（与上面两组同构 ✓）——
            // 范围：`components/side_bar.dart` 的 `showSideBar` 各调用点（漫画页收藏 / 选择章节 / 评论页）
            // + 收藏页「文件夹选择」✓。
            _SwitchSetting(
              title: "Dim sidebar".tl,
              settingKey: "sideBarDim",
              useDeviceSettings: useDeviceSpecificSettings,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Sidebar style".tl,
              settingKey: "sideBarSurfaceMode",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "opaque": "Opaque (cover)".tl,
                "transparent": "Translucent".tl,
                "off": "Off".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Sidebar background".tl,
              settingKey: "sideBarSurfaceTint",
              useDeviceSettings: useDeviceSpecificSettings,
              optionTranslation: {
                "darken": "Darken".tl,
                "lighten": "Lighten".tl,
                "none": "No tint".tl,
              },
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            _SliderSetting(
              title: "Sidebar contrast".tl,
              settingsIndex: "sideBarSurfaceTintStrength",
              useDeviceSettings: useDeviceSpecificSettings,
              interval: 0.02,
              min: 0.0,
              max: 0.6,
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
          ], // ← N1：二级页面自定义项隐藏到此结束 ✓
        ],
      ),
    );
  }
}
