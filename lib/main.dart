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
      backgroundColor: WidgetStatePropertyAll(windowOverlayColor()),
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
    // 「文字 / 描边 / 实色 / tonal 按钮」的前景都跟随**全局文字色** ✓
    // （实测反馈："扫描 NAS / 导入" 这类按钮文字与字体色不跟随即此 ✗）。
    // 注意：
    //  - **不要**给 `iconButtonTheme` 接全局文字色 ✗ —— 那会让图标跟着文字变色（已修过一次）；
    //  - 禁用态保留透明度（`fg @0.38`），避免"看起来可点" ✗。
    final overlayFg = globalTextColor();
    WidgetStateProperty<Color?>? overlayFgProp(Color fg) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return fg.toOpacity(0.38);
          }
          return fg;
        });
    // ─── P8 胶囊按钮规范（见 doc-private/03-implementation/07-background-and-color-picker.md）───
    // 底色 = 遮罩色（`windowOverlayColor()` ✓）、文字 = 全局文字色（`globalTextColor()` ✓）、
    // **文字水平+垂直居中** ✓、胶囊形状 ✓、`AppSpace` 令牌化间距 ✓、禁用态 0.38 ✓。
    // 直角模式（`windowOverlayBorderRadius()` 为 null）下形状退化为直角 ✓，尊重用户的形状设置。
    final pillShape = windowOverlayBorderRadius() == null
        ? const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          )
        : const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder());
    final pillButtonStyle = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(windowOverlayColor()),
      foregroundColor: overlayFg == null ? null : overlayFgProp(overlayFg),
      // 文字**横纵都居中** ✓
      alignment: Alignment.center,
      // 高度 **44** = 主页「扫描 NAS」实测高度 ✓（用户指定以它为全局标准 ✓）。
      // "细长"靠**收窄水平内边距**（AppSpace.sm ✓）解决；行内贴边则在**行**侧留呼吸 ✓。
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpace.sm),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: pillShape,
    );
    final scheme = SeedColorScheme.fromSeeds(
      primaryKey: primary,
      secondaryKey: secondary,
      tertiaryKey: tertiary,
      brightness: brightness,
      tones: FlexTones.vividBackground(brightness),
    );
    // 供「窗口/按钮背景」取"跟随系统"的颜色：用**中性容器色**（不是主题色系），
    // 这样遮罩色与由主题色控制的 tag/滑条颜色能区分开。
    // ⚠️ 此处禁止调用 Theme.of（主题尚未建立会启动异常）。
    systemContainerColorCache = scheme.surfaceContainerHigh;
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
      // ↓ 以下四类 = **胶囊按钮**，统一走 P8 规范（遮罩底色 + 全局文字色 + 居中 + 胶囊 ✓）。
      // `TextButton` 也纳入 ✓ —— 它同样有遮罩底色（`overlayButtonStyle` ✓），
      // 且**垂直内边距 4→8、高度 36→44** 后可彻底消除"文字被压窄/裁切"✗（实测反馈 ✓）。
      textButtonTheme: TextButtonThemeData(style: pillButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: pillButtonStyle),
      filledButtonTheme: FilledButtonThemeData(style: pillButtonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: pillButtonStyle),
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
