part of 'settings_page.dart';

/// ⭐ 2026-11-14（同步上游 #142 ✓）：**漫画更新**设置页 ✓
/// 与「APP 版本检查」（在 About 页 ✓）分开 ✓，可配置：启动检查 / 间隔 / 已有更新时跳过 ✓。
class UpdatesSettings extends StatefulWidget {
  const UpdatesSettings({super.key});

  @override
  State<UpdatesSettings> createState() => _UpdatesSettingsState();
}

class _UpdatesSettingsState extends State<UpdatesSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Updates".tl)),
        _SwitchSetting(
          title: "Check for comic updates on app start".tl,
          settingKey: "comicUpdateCheckOnStart",
        ).toSliver(),
        SelectSetting(
          title: "Update check interval".tl,
          settingKey: "comicUpdateCheckInterval",
          help: "Minimum time between checks for the same comic.".tl,
          optionTranslation: {
            "1": "1 hour".tl,
            "6": "6 hours".tl,
            "12": "12 hours".tl,
            "24": "1 day".tl,
            "48": "2 days".tl,
            "72": "3 days".tl,
          },
        ).toSliver(),
        _SwitchSetting(
          title: "Skip comics already marked as updated".tl,
          subtitle:
              "Saves bandwidth by not re-checking comics that already have a pending update."
                  .tl,
          settingKey: "skipCheckIfHasNewUpdate",
        ).toSliver(),
      ],
    );
  }
}
