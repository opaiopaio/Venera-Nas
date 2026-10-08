part of 'settings_page.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  Widget build(BuildContext context) {
    // ⭐ 建立设置依赖（A5 修复）：外观设置变化时由框架**精准重建本页** ✓，
    // 这样「主题颜色」等行的预览色块才会**实时刷新** ✓。
    // 原先本页没有任何设置依赖 ✗ → 改完颜色预览不动 ✗（要重进页面才变 ✓）。
    // ⚠️ 禁止改用 `App.forceRebuild()` 的 element 树遍历 ✗（曾导致严重渲染鬼影 ✗），
    // 详见 doc-private/03-implementation/11-refresh-mechanism.md
    AppSettingsScope.of(context);

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        _SettingPartTitle(title: "Theme".tl, icon: Icons.palette),
        SelectSetting(
          title: "Theme Mode".tl,
          settingKey: "theme_mode",
          optionTranslation: {
            "system": "System".tl,
            "light": "Light".tl,
            "dark": "Dark".tl,
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        ColorSettingTile(
          title: "Theme Color".tl,
          settingValue: (appdata.settings['color'] ?? 'system').toString(),
          allowSystem: true,
          // 一套系统：主题色同时决定按钮/卡片/控件的底色；「透明」= 不要底色。
          allowTransparent: true,
          onPicked: (value) async {
            appdata.settings['color'] = value;
            await appdata.saveData();
            await App.init();
            App.forceRebuild();
          },
        ).toSliver(),
        // ⭐ A7：全局「图标颜色」✓ —— 控制**全部图标**的颜色 ✓。
        // 设计约束：**独立于字体颜色** ✗（历史上用文字色染图标是错的 ✗，已从 getTheme 移除 ✓）；
        // 默认 `system` = **不覆盖** ✓（图标继续跟随主题 ✓），只有显式选色后才注入 ✓；
        // 各处**显式传 `color:`** 的图标（危险色/白色角标等 ✓）不受影响 ✓（IconTheme 只作兜底 ✓）。
        ColorSettingTile(
          title: "Icon Color".tl,
          settingValue: (appdata.settings['globalIconColor'] ?? 'system')
              .toString(),
          allowSystem: true,
          // `system` = 跟随主题 → 预览用**默认图标色**（iconTheme 前景色 ✓），
          // 不能用 `primary` ✗（那是主题/强调色 ✗，用户实测反馈过 ✓）。
          systemPreview:
              Theme.of(context).iconTheme.color ??
              Theme.of(context).colorScheme.onSurfaceVariant,
          onPicked: (value) async {
            appdata.settings['globalIconColor'] = value;
            await appdata.saveData();
            App.forceRebuild();
          },
        ).toSliver(),
        // ⭐ L1：「标签颜色」模式开关（跟随遮罩 / 跟随主题 ✓，key `tagColorMode`）
        // 已按用户要求**删除** ✗ —— 标签底色改由下方「标签背景颜色 / 不透明度」**独立控制** ✓
        //（想用主题色时，把「标签背景颜色」显式设成对应颜色即可 ✓）。
        _SettingPartTitle(title: "Background".tl, icon: Icons.wallpaper),
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
          interval: 0.05,
          min: 0.0,
          max: 1.0,
          onChanged: () => App.forceRebuild(),
        ).toSliver(),
        SelectSetting(
          title: "Image fit".tl,
          settingKey: "backgroundImageFit",
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
        _SettingPartTitle(title: "Window & controls".tl, icon: Icons.widgets),
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
          SelectSetting(
            title: "Corner style".tl,
            settingKey: "windowOverlayCorner",
            optionTranslation: {"rounded": "Rounded".tl, "square": "Square".tl},
            onChanged: () => App.forceRebuild(),
          ).toSliver(),
        ], // ← N1：跟随主题时隐藏到此结束 ✓
        _SettingPartTitle(title: "Secondary page".tl, icon: Icons.layers),
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
        _SettingPartTitle(title: "Text".tl, icon: Icons.text_fields),
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
        _SettingPartTitle(title: "Comic Display".tl, icon: Icons.grid_view),
        SelectSetting(
          title: "Display mode of comic tile".tl,
          settingKey: "comicDisplayMode",
          optionTranslation: {"detailed": "Detailed".tl, "brief": "Brief".tl},
        ).toSliver(),
        _SliderSetting(
          title: "Size of comic tile".tl,
          settingsIndex: "comicTileScale",
          interval: 0.05,
          min: 0.5,
          max: 1.5,
        ).toSliver(),
        SelectSetting(
          title: "Display mode of comic list".tl,
          settingKey: "comicListDisplayMode",
          optionTranslation: {
            "paging": "Paging".tl,
            "continuous": "Continuous".tl,
          },
        ).toSliver(),
      ],
    );
  }
}

/// 自定义字体文件设置行：选择 / 清除。
class _FontFileTile extends StatelessWidget {
  const _FontFileTile();

  static const _exts = ['ttf', 'otf', 'ttc'];

  @override
  Widget build(BuildContext context) {
    final name = (appdata.settings['globalFontFile'] ?? '').toString();
    final path = customFontPath(name);
    final file = (path != null && File(path).existsSync()) ? File(path) : null;
    final source = (appdata.settings['globalFontSource'] ?? '').toString();
    return ListTile(
      title: Text("Custom font file".tl),
      subtitle: file == null
          ? null
          : Text(
              source.isEmpty ? file.path : source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // P8：标准 `TextButton` → 应用自绘 `Button`（一套体系 ✓，高度锁 32 ✓）
          Button.normal(
            onPressed: () => _pick(context),
            child: Text("Select file".tl),
          ),
          if (file != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: "Clear".tl,
              onPressed: _clear,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await selectFile(ext: _exts);
    if (result == null) return;
    try {
      final dir = Directory(customFontDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = result.path.split('.').last.toLowerCase();
      // 清掉旧字体，只保留一份（与背景图同样的处理）
      for (final entity in dir.listSync()) {
        if (entity is File) entity.deleteSync();
      }
      // 文件名也用**唯一名**：与背景图同理，避免任何按路径复用旧文件
      final name = 'custom_${DateTime.now().millisecondsSinceEpoch}.$ext';
      File(result.path).copySync('${dir.path}/$name');
      appdata.settings['globalFontFile'] = name;
      appdata.settings['globalFontSource'] = result.path;
      await appdata.saveData();
      await loadCustomFont();
      App.forceRebuild();
    } catch (e) {
      if (context.mounted) context.showMessage(message: e.toString());
    }
  }

  Future<void> _clear() async {
    try {
      final dir = Directory(customFontDir);
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is File) entity.deleteSync();
        }
      }
    } catch (_) {}
    appdata.settings['globalFontFile'] = '';
    appdata.settings['globalFontSource'] = '';
    await appdata.saveData();
    await loadCustomFont();
    App.forceRebuild();
  }
}

/// 背景图片设置行：选择 / 清除。
class _BackgroundImageTile extends StatelessWidget {
  const _BackgroundImageTile();

  static const _supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  ];

  @override
  Widget build(BuildContext context) {
    final settingName = (appdata.settings['backgroundImage'] ?? '').toString();
    final path = settingName.isEmpty
        ? null
        : '${App.dataPath}/background/$settingName';
    final file = (path != null && File(path).existsSync()) ? File(path) : null;
    final source = (appdata.settings['backgroundImageSource'] ?? '').toString();
    // 设置里指向的图片已不存在（例如手动删掉了文件）时视为未选择，
    // 并顺手清掉这个失效引用，避免一直指向一个不存在的文件。
    if (settingName.isNotEmpty && file == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = (appdata.settings['backgroundImage'] ?? '').toString();
        if (current == settingName) {
          appdata.settings['backgroundImage'] = '';
          appdata.saveData();
          App.forceRebuild();
        }
      });
    }
    return ListTile(
      title: Text("Background image".tl),
      isThreeLine: file != null,
      subtitle: file == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 优先显示**原始选取文件**的名字与完整路径（程序内部会复制重命名，
                // 只显示内部路径会让人以为文件名/地址不对）。
                Text(
                  source.isEmpty
                      ? file.uri.pathSegments.last
                      : source.split(RegExp(r'[\\/]')).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  source.isEmpty ? file.path : source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (source.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // P8：标准 `TextButton` → 应用自绘 `Button`（一套体系 ✓，高度锁 32 ✓）
          Button.normal(
            onPressed: () => _pick(context),
            child: Text("Select image".tl),
          ),
          if (file != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: "Clear".tl,
              onPressed: _clear,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    var result = await selectFile(ext: _supportedExtensions);
    if (result == null) return;
    try {
      final dir = Directory('${App.dataPath}/background');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      // 清掉旧图，只保留一张
      for (final entity in dir.listSync()) {
        if (entity is File) {
          entity.deleteSync();
        }
      }
      final ext = result.path.split('.').last.toLowerCase();
      // **文件名必须每次唯一**：`FileImage` / `Image.file` 按**路径**缓存，
      // 若沿用固定名（`background.<ext>`），覆盖同名文件后：
      // ① ImageCache 命中旧位图；② 新 provider 与旧 provider 相等 → `Image`
      // 不会重启图片流 → 界面一直显示上一张（本 bug 的根因）。
      final previous = (appdata.settings['backgroundImage'] ?? '').toString();
      final name = 'background_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final target = File('${dir.path}/$name');
      File(result.path).copySync(target.path);
      // 顺手把旧图从缓存里清掉（文件已在上面的循环里删除，这里只是释放缓存）
      if (previous.isNotEmpty && previous != name) {
        await FileImage(File('${dir.path}/$previous')).evict();
      }
      await FileImage(target).evict();
      appdata.settings['backgroundImage'] = name;
      // 记录**原始选取路径**，用于在设置页显示真实的文件地址与文件名。
      appdata.settings['backgroundImageSource'] = result.path;
      await appdata.saveData();
      App.forceRebuild();
    } catch (e) {
      if (context.mounted) {
        context.showMessage(message: e.toString());
      }
    }
  }

  Future<void> _clear() async {
    try {
      final dir = Directory('${App.dataPath}/background');
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is File) {
            entity.deleteSync();
          }
        }
      }
    } catch (_) {}
    appdata.settings['backgroundImage'] = '';
    appdata.settings['backgroundImageSource'] = '';
    await appdata.saveData();
    App.forceRebuild();
  }
}
