import 'dart:async';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/comic_source/comic_source.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';
import 'package:venera_nas/pages/auth_page.dart';
import 'package:venera_nas/pages/comic_details_page/comic_page.dart';
import 'package:venera_nas/pages/main_page.dart';
import 'package:venera_nas/utils/app_links.dart';
import 'package:venera_nas/utils/background_download.dart';
import 'package:venera_nas/utils/io.dart';
import 'package:venera_nas/utils/translations.dart';
import 'package:window_manager/window_manager.dart';
import 'components/components.dart';
import 'components/window_frame.dart';
import 'foundation/app.dart';
import 'foundation/app_page_route.dart';
import 'foundation/appdata.dart';
import 'headless.dart';
import 'init.dart';
import 'package:venera_nas/foundation/app_theme.dart';

void main(List<String> args) {
  if (args.contains('--headless')) {
    runHeadlessMode(args);
    return;
  }
  if (runWebViewTitleBarWidget(args)) return;
  overrideIO(() {
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();
        await init();
        // 加载自定义字体文件（若已配置）
        await loadCustomFont();
        runApp(const MyApp());
        if (App.isDesktop) {
          await windowManager.ensureInitialized();
          windowManager.waitUntilReadyToShow().then((_) async {
            await windowManager.setTitleBarStyle(
              TitleBarStyle.hidden,
              windowButtonVisibility: App.isMacOS,
            );
            if (App.isLinux) {
              await windowManager.setBackgroundColor(Colors.transparent);
            }
            await windowManager.setMinimumSize(const Size(500, 600));
            var placement = await WindowPlacement.loadFromFile();
            if (App.isLinux) {
              await windowManager.show();
              await placement.applyToWindow();
            } else {
              await placement.applyToWindow();
              await windowManager.show();
            }

            WindowPlacement.loop();
          });
        }
      },
      (error, stack) {
        Log.error("Unhandled Exception", error, stack);
      },
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// 主题级设置（字体颜色/字体/字号/阴影、主题色、语言…）是在本 State 的 `build`
  /// 里算进 `MaterialApp.theme`/`textScaler`/`locale` 的 —— 它们位于
  /// `AppSettingsScope` **之上**，scope 的依赖传播覆盖不到 ✗。
  /// 所以这里**直接订阅设置**：设置一变就重建本 State → 主题级选项即时生效
  /// （历史实现靠 `forceRebuild()` 里的 `setState` 达成，删遍历时被一并删掉了，
  /// 导致"字体相关所有选项失效"的回归）。
  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    App.registerForceRebuild(forceRebuild);
    appdata.settings.addListener(_onSettingsChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    checkUpdates();
    if (App.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkClipboardForVeneraLink();
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    appdata.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  bool isAuthPageActive = false;
  bool _sessionAuthenticated = false;

  OverlayEntry? hideContentOverlay;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && App.isMobile) {
      _checkClipboardForVeneraLink();
      // 重新同步后台下载前台服务：OS 可能在后台期间杀掉了它。
      // 在不支持的平台上（iOS / 桌面）为 no-op。
      BackgroundDownload.instance.onAppResumed();
    }
    if (!App.isMobile || !appdata.settings['authorizationRequired']) {
      return;
    }
    if (state == AppLifecycleState.inactive && hideContentOverlay == null) {
      hideContentOverlay = OverlayEntry(
        builder: (context) {
          return Positioned.fill(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: App.rootContext.colorScheme.surface,
            ),
          );
        },
      );
      Overlay.of(App.rootContext).insert(hideContentOverlay!);
    } else if (hideContentOverlay != null &&
        state == AppLifecycleState.resumed) {
      hideContentOverlay!.remove();
      hideContentOverlay = null;
    }
    if (state == AppLifecycleState.hidden &&
        !isAuthPageActive &&
        !IO.isSelectingFiles) {
      _sessionAuthenticated = false;
      isAuthPageActive = true;
      App.rootContext.to(
        () => AuthPage(
          onSuccessfulAuth: () {
            _sessionAuthenticated = true;
            App.rootContext.pop();
            isAuthPageActive = false;
          },
        ),
      );
    }
    super.didChangeAppLifecycleState(state);
  }

  void _checkClipboardForVeneraLink() async {
    try {
      String? text;

      if (Platform.isIOS) {
        // On iOS, use native method to check and read clipboard in one call.
        // This avoids triggering the system paste notification for non-venera URLs.
        text = await const MethodChannel(
          'venera/method_channel',
        ).invokeMethod<String>('getVeneraClipboardLink');
        if (text == null) return;
      } else {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text == null) return;
        text = data!.text!;
      }

      final uri = parseVeneraLink(text);
      if (uri == null) return;

      final lastHandled =
          appdata.implicitData['lastHandledClipboard'] as String?;
      if (uri.toString() == lastHandled) return;
      appdata.implicitData['lastHandledClipboard'] = uri.toString();
      await appdata.writeImplicitData();

      final comic = parseComicFromUri(uri);
      if (comic == null) return;

      if (_isViewingComic(comic.id, comic.sourceKey)) return;

      // Extract title from the text line before the URL
      final uriMatch = RegExp(r'venera://\S+').firstMatch(text);
      final beforeUrl = text.substring(0, uriMatch?.start ?? 0).trim();
      final title = beforeUrl.isNotEmpty ? beforeUrl : null;

      final source = ComicSource.find(comic.sourceKey);
      final context = App.rootContext;
      if (!context.mounted) return;

      final displayName = title ?? comic.id;
      if (source != null) {
        showConfirmDialog(
          context: context,
          title: 'Open comic'.tl,
          content: '${'Open comic'.tl}: $displayName',
          onConfirm: () {
            App.mainNavigatorKey?.currentContext?.to(() {
              return ComicPage(id: comic.id, sourceKey: comic.sourceKey);
            });
          },
        );
      }
    } catch (e) {
      Log.warning("App", "Failed to handle clipboard link: $e");
    }
  }

  bool _isViewingComic(String id, String sourceKey) {
    final navContext = App.mainNavigatorKey?.currentContext;
    if (navContext == null) return false;
    ComicPage? found;
    void visitor(Element el) {
      if (found != null) return;
      if (el.widget is ComicPage) {
        found = el.widget as ComicPage;
        return;
      }
      el.visitChildren(visitor);
    }

    (navContext as Element).visitChildren(visitor);
    return found?.id == id && found?.sourceKey == sourceKey;
  }

  void forceRebuild() {
    // **只通知设置 scope**：依赖它的控件（`AppSettingsScope.of`）由框架精准重建。
    //
    // ⚠️ 这里历史上是"遍历整棵 element 树 markNeedsBuild()"：它会打到
    // Navigator/Overlay 中**已退场但未销毁**的元素 → 残留图层/半渲染，
    // 表现为"页面被切成左右两半、中间一条能滚动的背景带、只有背景在动"的严重 bug。
    // **禁止**再退回那种做法；需要刷新时让对应控件依赖 `AppSettingsScope`。
    //
    // 在 build 阶段被调用时延后到帧末，避免 "markNeedsBuild during build"。
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appdata.settings.notifySettingsChanged();
      });
    } else {
      appdata.settings.notifySettingsChanged();
    }
  }

  Color translateColorSetting() {
    // 支持命名色（旧值）与 #RRGGBB（新值）；system/transparent 回退蓝色。
    return resolveColorSettingValue(appdata.settings['color'] as String?) ??
        Colors.blue;
  }

  ThemeData getTheme(
    Color primary,
    Color? secondary,
    Color? tertiary,
    Brightness brightness,
  ) {
    String? font;
    List<String>? fallback;
    if (App.isLinux || App.isWindows) {
      font = 'Noto Sans CJK';
      fallback = [
        'Segoe UI',
        'Noto Sans SC',
        'Noto Sans TC',
        'Noto Sans',
        'Microsoft YaHei',
        'PingFang SC',
        'Arial',
        'sans-serif',
      ];
    }
    // 启用了自定义背景且配置了「窗口/按钮背景」时，让全局的按钮也带上该底色，
    // 这样各处零散按钮（收藏页工具栏、搜索页设置/清除历史等）也能跟随层次设计。
    // 所有按钮统一走「窗口/按钮背景」这套设计：底色 = 遮罩色（未配置即透明），
    // 形状 = 圆角/直角设置。不再回退到主题色，也不依赖是否配置了遮罩色。
    final overlayButtonStyle = ButtonStyle(
      // ⭐ I1：图标按钮（`IconButton`）的底色也走**按钮独立入口** ✓ ——
      // 原先用 `windowOverlayColor()` ✗ → 与面板同色、且**不受「按钮背景」设置控制** ✗
      //（用户实测："只有图标的按钮都不受控，还是受窗口遮罩控制" ✓）。
      backgroundColor: WidgetStatePropertyAll(iconOverlayColor()),
      // 让按钮的底色方块更小、彼此不粘连。
      minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(windowOverlayRadius()),
        ),
      ),
    );
    // ⭐ H2 清理（2026-10-08）：原 `overlayFg` / `overlayFgProp`（M3 按钮前景与禁用态 0.38 ✓）
    // 与 `pillShape`（胶囊/直角形状 ✓）**已全部删除** ✗ —— 它们只服务于已移除的
    // `pillButtonStyle` ✗；现在：按钮前景/禁用态/形状全部由自绘 `Button` 内部统一处理 ✓
    //（`components/button.dart`：32 高 + 文字宽度两侧各 `AppSpace.lg(16)` + 胶囊 + 遮罩底
    //  + 全局文字色 + `onPressed == null` → 0.38 ✓）。
    // 注意：**不要**给 `iconButtonTheme` 接全局文字色 ✗ —— 那会让图标跟着文字变色（已修过一次）。
    // ⭐ H2 清理（2026-10-08）：原 `overlayFgProp`（M3 按钮的禁用态 0.38 前景 ✓）与
    // `pillShape`（胶囊/直角形状 ✓）**已删除** ✗ —— 它们只服务于已移除的 `pillButtonStyle` ✗；
    // 禁用态 0.38 现由自绘 `Button` 内部统一处理 ✓（`buttonColor`/`textColor` 判定 `onPressed == null` ✓）。
    // ⭐ H2 清理（2026-10-08）：原 `pillButtonStyle`（给 M3 的 Text/Outlined/Filled/Elevated
    // 注入遮罩底色 + 32 高 + 胶囊 ✓）**已删除** ✗ —— 实测 M3 变体默认样式会压过主题 ✗
    //（"看着在管其实没管" ✗）；全项目 M3 按钮已全部改为应用自绘 `Button` ✓（components/button.dart ✓，
    // 规格 = 32 高 + 文字宽度两侧各 AppSpace.lg(16) 延伸 + 胶囊 + 遮罩底 + 全局文字色 ✓）。
    var scheme = SeedColorScheme.fromSeeds(
      primaryKey: primary,
      secondaryKey: secondary,
      tertiaryKey: tertiary,
      brightness: brightness,
      tones: FlexTones.vividBackground(brightness),
    );
    // ⭐ A6 修复：所选主题色**按原样**用于强调元素 ✓ ——
    // 原先只把所选色当 `primaryKey` **种子** ✗，M3 `SeedColorScheme` 会**派生色调** ✗
    // → 界面显示的是派生后的深浅色 ✗，与预览/所选**不符** ✗（用户实测反馈 ✓）。
    // 现在覆盖 `primary` / `primaryContainer`（滑条/开关/选中态用的就是这两个 ✓），
    // 对比色 `onPrimary/onPrimaryContainer` 按**亮度**计算 ✓，保证可读性 ✓。
    final onPicked =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
        ? Colors.white
        : Colors.black;
    scheme = scheme.copyWith(
      primary: primary,
      onPrimary: onPicked,
      primaryContainer: primary,
      onPrimaryContainer: onPicked,
    );
    // 供「窗口/按钮背景」取"跟随系统"的颜色：用**中性容器色**（不是主题色系），
    // 这样遮罩色与由主题色控制的 tag/滑条颜色能区分开。
    // ⚠️ 此处禁止调用 Theme.of（主题尚未建立会启动异常）。
    // ⭐ B1 修复（审计 AP1-B1 ✓）：**只有"当前生效亮度"的那次调用才写缓存** ✗→✓ ——
    // 原先此处**无条件**写同一个全局变量 ✗，而 `MaterialApp` 会先求值 `theme`(light ✓)、
    // 后求值 `darkTheme`(dark ✓) → **暗色恒覆盖亮色** ✓ → 亮色界面的窗口/胶囊/图标/标签四项
    // `system` 遮罩全部拿到**近黑灰** ✗（用户反馈"黑不溜秋"的**真根因** ✓）。
    // 生效亮度 = `theme_mode`（system 时取平台亮度 ✓）。
    final themeMode = appdata.settings['theme_mode'] ?? 'system';
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final effectiveDark =
        themeMode == 'dark' || (themeMode == 'system' && platformDark);
    if (brightness == (effectiveDark ? Brightness.dark : Brightness.light)) {
      systemContainerColorCache = scheme.surfaceContainerHigh;
    }
    // ⭐ Q1 修正（用户反馈 ✓）：先用过 `secondaryContainer` ✗（深色主题下偏深 → "深很多" ✗）、
    // 又用过 `surfaceContainerHighest` ✗（**几乎中性、不随种子色变化** ✗，深色下即深灰 →
    // "黑不溜秋、不随主题色变动" ✗）。正解 = M3 的 **fixed 系色** ✓：
    // `secondaryFixed` **跟随种子色** ✓ 且**明暗主题下都保持浅色** ✓（正是 M3 为"固定浅色容器"设计的 ✓）。
    themeButtonColorCache = scheme.secondaryFixed;
    // ⭐ AP1-A4（审计 ✓）：原此处写 `themeSourceTabColorCache = scheme.secondaryContainer` ✗ ——
    // 因 AG1 后"跟随系统"改取**系统按钮色**（`themeButtonColorCache` ✓），该缓存**已无读取点** ✓
    //（只写不读的死代码 ✗）→ 连同字段一并删除 ✓（零行为影响 ✓）。
    final gStyle = globalTextStyle();
    var theme = ThemeData(
      colorScheme: scheme,
      fontFamily: font,
      fontFamilyFallback: fallback,
      // 启用自定义背景时，让页面 Scaffold 透明，背景层才能透出。
      scaffoldBackgroundColor: AppBackground.isActive
          ? Colors.transparent
          : null,
      iconButtonTheme: IconButtonThemeData(style: overlayButtonStyle),
      // ⭐ E1-④：`showDialog` 类弹层的暗罩同样受「突出二级菜单」开关控制 ✓ ——
      // 这类弹层（主页「扫描 NAS / 导入」、漫画源配置等 ✓）原先走 Flutter 默认
      // `Colors.black54` ✗（**不受开关控制** ✓，用户实测反馈 ✓）；`PopUpWidget`
      // 路由则在 `components/pop_up_widget.dart` 里单独处理 ✓。
      // 规则与 `PopUpWidget` 一致 ✓：开关关 → 全透明（统一无暗罩 ✓）；
      // 开 / 未设置 → `Colors.black54` ✓（保持原有行为 ✓，零回归 ✓）。
      dialogTheme: DialogThemeData(
        barrierColor: appdata.settings['secondaryMenuDim'] == false
            ? Colors.transparent
            : Colors.black54,
      ),
      // ⭐ F1-②：分段 tab（`AppTabBar` ✓，图片收藏的「标签/作者/漫画」✓）的**选中文字色**
      // 继承**全局文字色** ✓ —— 与分类页 tag（`MaskChip` ✓ 不指定文字色、继承环境样式 ✓）
      // 同一约定 ✓。原先走 M3 默认（主题色 ✗）→ 只改底色时观感"依旧跟随主题" ✗
      //（用户实测反馈"切换没反应" ✓）。未设置全局文字色时 `gStyle?.color` 为 null ✓
      // → 不注入 ✓ → 继续走 M3 默认 ✓（零回归 ✓）。
      tabBarTheme: TabBarThemeData(labelColor: gStyle?.color),
      // ⭐ H2 清理（2026-10-08）：**已移除**四类 M3 按钮的主题注入 ✗
      //（原 `textButtonTheme` / `outlinedButtonTheme` / `filledButtonTheme` / `elevatedButtonTheme`
      //  = `pillButtonStyle` ✓）。原因：M3 的**变体默认样式会压过主题** ✗（实测：`minimumSize`
      //  / `padding` / `shape` 注入后仍渲染为 40 高 M3 圆角矩形 ✗ "看着在管其实没管" ✗），
      // 且全项目 95 处 M3 按钮**已全部替换为应用自绘 `Button`** ✓（自上而下统一 ✓）。
      // 该注入留着只会误导后人 ✗ → 删除 ✓；下面 `iconButtonTheme`（`overlayButtonStyle` ✓）仍然生效 ✓ 保留 ✓。
    );
    // 全局文字（字体 + 颜色）：注入主题文字，做到"大致全控制"。
    // 注 1：所有按钮的**文字**都跟随全局文字色 ✓（text/outlined/filled/tonal ✓，见上方注入）；
    //       仅 `iconButtonTheme` 与 `iconTheme` 不接 ✓ —— 图标保持主题前景色，
    //       否则侧栏/设置图标会跟着文字变色 ✗（已踩过一次）。
    // 注 2：**不要**把全局文字色注入 `iconTheme` ✗（同上）。
    if (gStyle != null) {
      final fg = gStyle.color;
      // ListTile 的标题/副标题样式（全局文字样式自身已含颜色/字体/阴影/发光 ✓）
      final titleStyle = theme.textTheme.bodyLarge?.merge(gStyle);
      final subStyle = theme.textTheme.bodyMedium?.merge(gStyle);
      theme = theme.copyWith(
        // 颜色/字体/**阴影/发光** 注入整套主题文字（按钮、标签栏等控件的文字才会生效）
        textTheme: decorateTextTheme(
          theme.textTheme.apply(
            fontFamily: gStyle.fontFamily,
            bodyColor: fg,
            displayColor: fg,
          ),
        ),
        primaryTextTheme: decorateTextTheme(
          theme.primaryTextTheme.apply(
            fontFamily: gStyle.fontFamily,
            bodyColor: fg,
            displayColor: fg,
          ),
        ),
        // ⚠️ **必须同时更新 `listTileTheme`**：`ThemeData` 在**构造时**就把
        // ListTile 的默认文字样式算成了 `colorScheme.onSurface`（近黑 ✗），
        // 之后 `copyWith(textTheme:)` **不会重算**它 → 所有基于 `ListTile` 的
        // 设置行都会"不跟随全局文字颜色"（实测：行内 innerDefault=onSurface ✗，
        // 而 innerThemeBodyLarge=全局色 ✓）。这里显式接上全局文字样式 ✓。
        listTileTheme: theme.listTileTheme.copyWith(
          titleTextStyle: titleStyle,
          subtitleTextStyle: subStyle,
          leadingAndTrailingTextStyle: subStyle,
          // ⭐ B1/B2（用户实测：侧栏「本地/网络」、主页「同步数据」刷新图标
          // 始终"固定黑"、不随「图标颜色」变化 ✗）真因：
          // `ThemeData` 在**构造时**就把 `ListTileThemeData.iconColor` 烘焙成
          // `colorScheme.onSurfaceVariant`（近黑 ✗），之后 `copyWith(textTheme:)`
          // **不会重算** ✗ —— 与之前 `listTileTheme` 文字色是同一个坑 ✓。
          // ListTile 的 leading/trailing 图标由 `ListTileThemeData.iconColor` 决定 ✗，
          // 优先级**高于** `iconTheme` ✗ → 不显式接上，图标就永远是黑色 ✗。
          iconColor:
              resolveColorSettingValue(
                appdata.settings['globalIconColor'] as String?,
              ) ??
              theme.iconTheme.color,
        ),
      );
    }
    // ⭐ A7：全局「图标颜色」✓ —— 默认 `system`（或 `transparent`）时 `resolveColorSettingValue`
    // 返回 null → **不注入** ✗（图标继续跟随主题 ✓）；只有用户**显式选色**后才覆盖 ✓。
    // ⚠️ **必须同步 `iconButtonTheme`**：`IconButtonThemeData` 优先级高于 `iconTheme` ✗，
    // 只改 `iconTheme` 会出现"设置了没效果" ✗。
    // 说明：`IconTheme` 只作**兜底** ✓ —— 各处显式传 `color:` 的图标（危险色/白色角标 ✓）
    // 保持自身颜色 ✓，不会被本设置误染 ✓；图标尺寸/形状不受影响 ✓。
    final iconColor = resolveColorSettingValue(
      appdata.settings['globalIconColor'] as String?,
    );
    if (iconColor != null) {
      theme = theme.copyWith(
        iconTheme: theme.iconTheme.copyWith(color: iconColor),
        primaryIconTheme: theme.primaryIconTheme.copyWith(color: iconColor),
        iconButtonTheme: IconButtonThemeData(
          style:
              theme.iconButtonTheme.style?.copyWith(
                foregroundColor: WidgetStatePropertyAll(iconColor),
                iconColor: WidgetStatePropertyAll(iconColor),
              ) ??
              IconButton.styleFrom(foregroundColor: iconColor),
        ),
      );
    }
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (appdata.settings['authorizationRequired']) {
      // AuthPage 不是直接作为 home，而是通过 Builder 延迟 push，
      // 确保 Navigator 从子树内部执行 push/pop，冷启动时过渡动画正常。
      home = Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_sessionAuthenticated || isAuthPageActive) return;
            isAuthPageActive = true;
            Navigator.of(context).push(
              AppPageRoute(
                builder: (_) => AuthPage(
                  onSuccessfulAuth: () {
                    _sessionAuthenticated = true;
                    Navigator.of(context).pop();
                    isAuthPageActive = false;
                    // 这是 **状态变化**（不是设置变化）：直接 setState 重建本 State
                    // 的子树即可（原先靠 forceRebuild() 的全树遍历，已废弃）。
                    setState(() {});
                  },
                ),
              ),
            );
          });
          return Stack(
            children: [
              const MainPage(),
              if (!_sessionAuthenticated)
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),
            ],
          );
        },
      );
    } else {
      home = const MainPage();
    }
    return DynamicColorBuilder(
      builder: (light, dark) {
        Color? primary, secondary, tertiary;
        if (appdata.settings['color'] != 'system' ||
            light == null ||
            dark == null) {
          primary = translateColorSetting();
        } else {
          primary = light.primary;
          secondary = light.secondary;
          tertiary = light.tertiary;
        }
        return MaterialApp(
          title: "VeneraNas",
          home: home,
          debugShowCheckedModeBanner: false,
          theme: getTheme(primary, secondary, tertiary, Brightness.light),
          navigatorKey: App.rootNavigatorKey,
          darkTheme: getTheme(primary, secondary, tertiary, Brightness.dark),
          themeMode: switch (appdata.settings['theme_mode']) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          color: Colors.transparent,
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: () {
            var lang = appdata.settings['language'];
            if (lang == 'system') {
              return null;
            }
            return switch (lang) {
              'zh-CN' => const Locale('zh', 'CN'),
              'zh-TW' => const Locale('zh', 'TW'),
              'en-US' => const Locale('en'),
              _ => null,
            };
          }(),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en'),
          ],
          builder: (context, widget) {
            ErrorWidget.builder = (details) {
              Log.error(
                "Unhandled Exception",
                "${details.exception}\n${details.stack}",
              );
              return Material(
                child: Center(child: Text(details.exception.toString())),
              );
            };
            if (widget != null) {
              // 全局文字：字号缩放 + 颜色/字体/阴影/发光（未配置时不干预，零回归）
              //
              // ⚠️ **必须在这里（最靠内）先包上 `textScaler`**：
              // 下面"桌面端顶部让位"等处还会用 `MediaQuery.of(builderContext).copyWith(...)`
              // 再造一层 MediaQuery（那时的 context 仍是**未缩放**的 1.0 ✗）。
              // 由于"最近的祖先获胜"，若 scaler 包在外面就会被那层覆盖掉 →
              // 表现为**调字号完全没反应**（实测确认：包装层内 19.6、页面仍是 14.0 ✗）。
              final textScale = globalFontScale();
              if (textScale != 1.0) {
                widget = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(
                      AppTextScale.clamp(textScale),
                    ),
                  ),
                  child: widget,
                );
              }

              /// 如果无法检测到状态栏高度设定指定高度
              /// https://github.com/flutter/flutter/issues/161086
              var isPaddingCheckError =
                  MediaQuery.of(context).viewPadding.top <= 0 ||
                  MediaQuery.of(context).viewPadding.top > 200;

              if (isPaddingCheckError && Platform.isAndroid) {
                widget = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    viewPadding: const EdgeInsets.only(top: 15, bottom: 15),
                    padding: const EdgeInsets.only(top: 15, bottom: 15),
                  ),
                  child: widget,
                );
              }

              // 全局顶部边界：桌面端页面内容整体让出窗口标题栏高度，
              // 放在**背景层之上、页面之下**——背景仍铺满全窗（含标题栏区域），
              // 而所有页面（滚动/固定栏）都无法进入标题栏。
              if (App.isDesktop) {
                widget = Padding(
                  padding: const EdgeInsets.only(top: kTitleBarHeight),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      padding: MediaQuery.of(context).padding.copyWith(top: 0),
                    ),
                    child: widget,
                  ),
                );
              }

              if (AppBackground.isActive) {
                // 自定义背景：垫在所有内容之下，并让页面透出。
                widget = Stack(
                  children: [
                    const Positioned.fill(child: AppBackground()),
                    widget,
                  ],
                );
              }

              final gTextStyle = globalTextStyle();
              if (gTextStyle != null) {
                widget = DefaultTextStyle.merge(
                  style: gTextStyle,
                  child: widget,
                );
              }

              widget = OverlayWidget(widget);
              if (App.isDesktop) {
                widget = _WindowFrameBackgroundSync(child: widget);
                widget = Shortcuts(
                  shortcuts: {
                    LogicalKeySet(LogicalKeyboardKey.escape):
                        VoidCallbackIntent(App.pop),
                  },
                  child: MouseBackDetector(
                    onTapDown: App.pop,
                    child: WindowFrame(widget),
                  ),
                );
              }
              // 设置变化的**唯一正确通路**：把设置 scope 挂在 Navigator 之上
              // （本 builder 的 widget 就是 Navigator），弹层/路由内容都是它的后代
              // → 声明依赖的控件由框架精准重建，取代 forceRebuild() 的全树遍历。
              return AppSettingsScope(
                child: _SystemUiProvider(
                  Material(
                    color: (App.isLinux || AppBackground.isActive)
                        ? Colors.transparent
                        : null,
                    child: widget,
                  ),
                ),
              );
            }
            throw ('widget is null');
          },
        );
      },
    );
  }
}

class _SystemUiProvider extends StatelessWidget {
  const _SystemUiProvider(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    var brightness = Theme.of(context).brightness;
    SystemUiOverlayStyle systemUiStyle;
    if (brightness == Brightness.light) {
      systemUiStyle = SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
    } else {
      systemUiStyle = SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: child,
    );
  }
}

/// 让桌面端窗口标题栏背景在启用自定义背景时变透明，使背景透出。
class _WindowFrameBackgroundSync extends StatefulWidget {
  const _WindowFrameBackgroundSync({required this.child});

  final Widget child;

  @override
  State<_WindowFrameBackgroundSync> createState() =>
      _WindowFrameBackgroundSyncState();
}

class _WindowFrameBackgroundSyncState
    extends State<_WindowFrameBackgroundSync> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        WindowFrame.of(
          context,
        ).setWindowFrameBackgroundTransparent(AppBackground.isActive);
      } catch (_) {
        // 非桌面端或不在窗口框架内时忽略。
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
