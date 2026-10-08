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
        // ⭐ D1：「标签颜色」模式 ✓ —— 让全项目**小标签（tag/chip）**可切换：
        // 「跟随遮罩」= `windowOverlayColor()`（与分类页标签一致 ✓，默认 ✓）
        // 或「跟随主题」= `colorScheme.secondaryContainer`（原样式 ✓）。
        // 取值 key：`tagColorMode` = `overlay`（默认）/ `theme` ✓。
        ListTile(
          title: Text("Tag Color".tl),
          subtitle: Text("Follow Mask or Theme".tl),
          trailing: Select(
            current: appdata.settings['tagColorMode'] == 'theme'
                ? "Follow Theme".tl
                : "Follow Mask".tl,
            values: ["Follow Mask".tl, "Follow Theme".tl],
            onTap: (index) {
              appdata.settings['tagColorMode'] = index == 0
                  ? 'overlay'
                  : 'theme';
              appdata.saveData();
              App.forceRebuild();
            },
          ),
        ).toSliver(),
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
          optionTranslation: {"rounded": "Rounded".tl, "square": "Square".tl},
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
