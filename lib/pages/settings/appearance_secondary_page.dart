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
    return PopUpWidgetScaffold(
      title: "Popup overlays".tl,
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
          // ⭐ 复查修复（2026-10-09 ✓）：**菜单外观三项移出上面的总开关** ✗→✓ ——
          // 专项复查发现 ✗：这三项原先落在 `if (secondaryPageFollowTheme != true)` 内部 ✓
          //（= "跟随主题时**隐藏**" ✓），但 `components/menu.dart` 读它们时**没有任何门禁** ✗
          // → 默认态下设置**看不见、却仍然生效** ✗（想改菜单外观还必须先关掉一个
          // **会同时改变二级页面**的总开关 ✗）→ 违反"隐藏项不应生效"的一致性 ✓。
          // 现按既定设计（用户原话"把菜单的样式和背景也**复刻**上去"✓ → 菜单属**独立**一类外观 ✓，
          // 见 changelog AR1 ✓）把它们**移出**该开关 ✓：
          // **菜单观感完全不变** ✗（读取点与默认值一处未动 ✓），只是设置**在默认态也可见、可改** ✓。
          // ⚠️ 二级页面自己的三项（样式 / 背景 / 对比度 ✓）**仍留在**该开关内 ✓，语义不变 ✗。
          SelectSetting(
            title: "Menu style".tl,
            settingKey: "menuSurfaceMode",
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
            interval: 0.02,
            min: 0.0,
            max: 0.6,
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
        ],
      ),
    );
  }
}
