part of 'settings_page.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  @override
  Widget build(BuildContext context) {
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
        _SettingPartTitle(title: "Background".tl, icon: Icons.wallpaper),
        const _BackgroundImageTile().toSliver(),
        ColorSettingTile(
          title: "Background color".tl,
          settingValue:
              (appdata.settings['backgroundColor'] ?? 'transparent').toString(),
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
        ColorSettingTile(
          title: "Window & control background".tl,
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
          title: "Window & control background opacity".tl,
          settingsIndex: "windowOverlayOpacity",
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
        _SettingPartTitle(title: "Secondary page".tl, icon: Icons.layers),
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
        _SettingPartTitle(title: "Text".tl, icon: Icons.text_fields),
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
          TextButton(
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
      final name = 'custom.$ext';
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
          TextButton(
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
      final name = 'background.$ext';
      File(result.path).copySync('${dir.path}/$name');
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
