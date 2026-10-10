part of 'settings_page.dart';

/// ⭐ AT1 → AU1 → AV1 → AY1 → **BA1**（用户实测 ✓，2026-10-09）：外观四个子页的路由统一用它 ✓ ——
/// 现在**继承 `PageRouteBuilder`（不再继承 `MaterialPageRoute`）** ✗→✓。
///
/// ⚠️ **BA1 真因（有代码证据 ✓）**：`MaterialPageRoute` 会把转场交给**主题的 `pageTransitionsTheme`** ✗，
/// 而**本 App 没有自定义它**（全项目 grep `pageTransitionsTheme` / `ZoomPageTransitionsBuilder` **零命中** ✓）
/// → 用的就是 **Flutter 的桌面默认 `ZoomPageTransitionsBuilder`** ✗ —— zoom 的**退场页会放大到 ~1.05 并淡出** ✓，
/// 正是用户描述的"**上一级朝我眼睛方向放大**"✓（用户补充澄清："上移指的是**像我方向**，不是纵坐标方向"✓）。
/// 旧路由（右栏那层的 `PageRouteBuilder(Duration.zero)` ✓，见 `settings_page.dart:254` ✓）本身无动画 ✓
/// → 那个缩放**只可能来自主题默认** ✓（我已用 grep 排除了 App 自定义主题转场 ✓）。
/// **修法** ✓：改继承 **`PageRouteBuilder`** ✓ —— 它**完全不查主题** ✗（转场只由 `buildTransitions` 决定 ✓），
/// 再覆写 `buildTransitions` 复用 App 自己的 `SlidePageTransitionBuilder(forceSlide: true)` ✓
/// → **旧页不再被 zoom** ✓、新页仍是**横向切入** ✓、且**与设置页同一份实现** ✓（满足 AY1"不搞差分"✓）。
///
/// 保留的历史约束（都已修好，勿回退 ✗）：
/// ① 不得用 `opaque: false` ✗（曾致**两层页面重合** ✓，提交 `f689cee` 回退 ✓）；
/// ② 不得让"有背景时进子页"**白闪** ✓ 或**一片空白** ✓（`af83093` / `3c74cd3` 已修 ✓）；
/// ③ 四个入口仍推在**右栏内层 Navigator** 上 ✓，且内层 `Navigator` 仍带 `ValueKey(currentPage)` ✓
///    → **AO1**（点左侧设置栏立即切换、不被覆盖 ✓）不得回归 ✗；
/// ④ 只用于**这四个外观子页** ✓，其它页面/子页/弹层的路由**不动** ✗（同类原则 ✓）。
class SettingsSubPageRoute<T> extends PageRouteBuilder<T> {
  SettingsSubPageRoute({required WidgetBuilder builder})
    : super(
        // ⭐ 复查修复（2026-10-09 ✓）：**补回 `Semantics(scopesRoute: true, explicitChildNodes: true)`** ✗→✓ ——
        // `MaterialPageRoute.buildPage` 自带这层无障碍"路由作用域"边界 ✓，而本类已改继承
        // `PageRouteBuilder` ✗ → 该语义**丢失** ✗（读屏器会跨路由朗读 ✓ = 无障碍回归 ✓）。
        // 本项目自己的 `AppPageRoute` 也是**显式补上**这一层 ✓ → 保持一致 ✓。
        pageBuilder: (context, animation, secondaryAnimation) => Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: builder(context),
        ),
        // ⭐ 时长走令牌 ✓（`AppMotion.medium` ✓，与 `AppPageRoute` 一致 ✓）
        transitionDuration: AppMotion.medium,
        reverseTransitionDuration: AppMotion.medium,
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // ⭐ AY1（用户要求 ✓）：复用 App 自己的横向切入 ✓ 并 `forceSlide: true` ✓
    //（任何情况都横切 ✓；同一份实现 ✓，不搞差分 ✗）。
    return SlidePageTransitionBuilder(
      forceSlide: true,
    ).buildTransitions(this, context, animation, secondaryAnimation, child);
  }
}

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
    // 详见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md
    AppSettingsScope.of(context);

    // ⭐ 2026-10-10（用户要求 ✓）：**按设备独立保存本页设置** ✓ —— 与「阅读」页同一套机制 ✓：
    // 启用后本设备改的值只写在本设备 ✓，同步来的配置不会覆盖它 ✓。
    final useDeviceSpecificSettings = appdata.settings
        .isDeviceSpecificSettingsEnabled();

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Appearance".tl)),
        // ⭐ 2026-10-10（用户要求 ✓）：**启用此设备特定设置** ✓ —— 与「阅读」页同款开关 ✓：
        // 启用后，本页各项只在本设备生效并保存 ✓，其它设备同步过来的配置不会覆盖它 ✓。
        SwitchListTile(
          title: Text("Enable device specific settings".tl),
          value: useDeviceSpecificSettings,
          onChanged: (b) {
            setState(() {
              appdata.settings.setEnabledDeviceSpecificSettings(b);
            });
            appdata.saveData();
          },
        ).toSliver(),
        _SettingPartTitle(title: "Theme".tl, icon: Icons.palette),
        SelectSetting(
          title: "Theme Mode".tl,
          settingKey: "theme_mode",
          useDeviceSettings: useDeviceSpecificSettings,
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
        // ⭐ N1：本区块已迁到**独立子页** ✓（`appearance_background_page.dart` ✓）——
        // 设置项与 key 完全不变 ✓，仅换位置 ✓；点这一行进入 ✓。
        // ⭐ AL1（用户要求 ✓）：恢复为**正常选项行** ✓（`ListTile` + `.toSliver()` ✓）——
        // 整行可点 ✓ 且**受「窗口背景」遮罩控制** ✓（此前用裸标题行 ✗：只有文字/箭头能点 ✗、
        // 且没有遮罩底色 ✗ = 用户所说"很诡异"✗）。
        ListTile(
          // ⭐ AM1（用户要求 ✓）：**保留区块图标** ✓（原 `_SettingPartTitle` 的样子 ✓）；
          // 图标颜色不写死 ✓ → 由 `listTileTheme` 统一（跟随「图标颜色」设置 ✓）。
          leading: const Icon(Icons.wallpaper, size: AppIconSize.lg),
          title: Text("Background".tl),
          trailing: const Icon(Icons.chevron_right),
          // ⭐ AO1（用户反馈 ✓）：入口改为推在**右栏的内层 Navigator** ✓ ——
          // 原先 `context.to(...)` ✗ 是**根 Navigator 的全屏弹层** ✗ → 它盖住整屏的点击层 ✗，
          // 点左边设置栏（发现/阅读中…）会被它的 barrier 吃掉 ✗ = "点不动、页面不跳转" ✓。
          // 改为内层 push ✓ → 左侧设置栏**始终可点** ✓（一次点击即切换 ✓）。
          onTap: () =>
              showPopUpWidget(context, const AppearanceBackgroundPage()),
        ).toSliver(),
        // ⭐ N1：本区块已迁到**独立子页** ✓（`appearance_window_page.dart` ✓）—— 设置项与 key 完全不变 ✓，仅换位置 ✓。
        ListTile(
          leading: const Icon(Icons.widgets, size: AppIconSize.lg),
          title: Text("Window & controls".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showPopUpWidget(context, const AppearanceWindowPage()),
        ).toSliver(),
        // ⭐ N1：本区块已迁到**独立子页** ✓（`appearance_secondary_page.dart` ✓）—— 设置项与 key 完全不变 ✓，仅换位置 ✓。
        ListTile(
          leading: const Icon(Icons.layers, size: AppIconSize.lg),
          title: Text("Popup overlays".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              showPopUpWidget(context, const AppearanceSecondaryPage()),
        ).toSliver(),
        // ⭐ N1：本区块已迁到**独立子页** ✓（`appearance_text_page.dart` ✓）—— 设置项与 key 完全不变 ✓，仅换位置 ✓。
        ListTile(
          leading: const Icon(Icons.text_fields, size: AppIconSize.lg),
          title: Text("Text".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showPopUpWidget(context, const AppearanceTextPage()),
        ).toSliver(),
        _SettingPartTitle(title: "Comic Display".tl, icon: Icons.grid_view),
        SelectSetting(
          title: "Display mode of comic tile".tl,
          settingKey: "comicDisplayMode",
          useDeviceSettings: useDeviceSpecificSettings,
          optionTranslation: {"detailed": "Detailed".tl, "brief": "Brief".tl},
        ).toSliver(),
        _SliderSetting(
          title: "Size of comic tile".tl,
          settingsIndex: "comicTileScale",
          useDeviceSettings: useDeviceSpecificSettings,
          interval: 0.05,
          min: 0.5,
          max: 1.5,
        ).toSliver(),
        SelectSetting(
          title: "Display mode of comic list".tl,
          settingKey: "comicListDisplayMode",
          useDeviceSettings: useDeviceSpecificSettings,
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
