part of 'settings_page.dart';

/// ⭐ N1：外观 →「Secondary page」**独立子页** ✓（用户规格：除「主题」「漫画显示」外全部子页化 ✓）。
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
    return PopUpWidgetScaffold(
      title: "Secondary page".tl,
      body: CustomScrollView(
        slivers: [
          // ⭐ N1：二级页面页总开关 ✓（默认开 = 用默认弹层 ✓；关才启用样式/背景/对比强度 ✓）
          _SwitchSetting(
            title: "Follow system theme".tl,
            subtitle: "On: use the default look; Off: customize below".tl,
            settingKey: "secondaryPageFollowTheme",
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
              onChanged: () => App.forceRebuild(),
            ).toSliver(),
            SelectSetting(
              title: "Secondary page style".tl,
              settingKey: "secondaryPageMode",
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
