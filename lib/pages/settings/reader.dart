part of 'settings_page.dart';

class ReaderSettings extends StatefulWidget {
  const ReaderSettings({
    super.key,
    this.onChanged,
    this.comicId,
    this.comicSource,
  });

  final void Function(String key)? onChanged;
  final String? comicId;
  final String? comicSource;

  @override
  State<ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends State<ReaderSettings> {
  bool _isChapterCommentsAtEndSupported() {
    String? readerMode;
    bool? showChapterComments;

    if (widget.comicId != null &&
        widget.comicSource != null &&
        appdata.settings.isComicSpecificSettingsEnabled(
          widget.comicId,
          widget.comicSource,
        )) {
      readerMode = appdata.settings.getReaderSetting(
        widget.comicId!,
        widget.comicSource!,
        'readerMode',
      );
      showChapterComments = appdata.settings.getReaderSetting(
        widget.comicId!,
        widget.comicSource!,
        'showChapterComments',
      );
    } else {
      readerMode = appdata.settings['readerMode'] as String?;
      showChapterComments = appdata.settings['showChapterComments'] as bool?;
    }

    // Must have showChapterComments enabled and be in gallery mode
    if (showChapterComments != true) return false;

    return readerMode == 'galleryLeftToRight' ||
        readerMode == 'galleryRightToLeft';
  }

  void _onShowChapterCommentsChanged() {
    // When showChapterComments is turned off, also turn off showChapterCommentsAtEnd
    bool? showChapterComments;

    if (widget.comicId != null &&
        widget.comicSource != null &&
        appdata.settings.isComicSpecificSettingsEnabled(
          widget.comicId,
          widget.comicSource,
        )) {
      showChapterComments = appdata.settings.getReaderSetting(
        widget.comicId!,
        widget.comicSource!,
        'showChapterComments',
      );
      if (showChapterComments != true) {
        appdata.settings.setReaderSetting(
          widget.comicId!,
          widget.comicSource!,
          'showChapterCommentsAtEnd',
          false,
        );
      }
    } else {
      showChapterComments = appdata.settings['showChapterComments'] as bool?;
      if (showChapterComments != true) {
        appdata.settings['showChapterCommentsAtEnd'] = false;
      }
    }

    setState(() {});
    widget.onChanged?.call("showChapterComments");
  }

  @override
  Widget build(BuildContext context) {
    final comicId = widget.comicId;
    final sourceKey = widget.comicSource;
    final key = "$comicId@$sourceKey";

    bool isEnabledSpecificSettings =
        comicId != null &&
        appdata.settings.isComicSpecificSettingsEnabled(comicId, sourceKey);
    bool useDeviceSpecificSettings =
        !isEnabledSpecificSettings &&
        appdata.settings.isDeviceSpecificSettingsEnabled();

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Reading".tl)),
        if (comicId != null && sourceKey != null)
          SliverMainAxisGroup(
            slivers: [
              SwitchListTile(
                title: Text("Enable comic specific settings".tl),
                value: isEnabledSpecificSettings,
                onChanged: (b) {
                  setState(() {
                    appdata.settings.setEnabledComicSpecificSettings(
                      comicId,
                      sourceKey,
                      b,
                    );
                  });
                },
              ).toSliver(),
              if (isEnabledSpecificSettings)
                Center(
                  child: Button.normal(
                    onPressed: () {
                      setState(() {
                        appdata.settings.resetComicReaderSettings(key);
                      });
                    },
                    child: Text(
                      "Clear specific reader settings for this comic".tl,
                    ),
                  ),
                ).toSliver(),
              SliverToBoxAdapter(child: Divider()),
            ],
          ),
        if (comicId == null)
          SliverMainAxisGroup(
            slivers: [
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
              if (useDeviceSpecificSettings)
                Center(
                  child: Button.normal(
                    onPressed: () {
                      setState(() {
                        appdata.settings.resetDeviceReaderSettings();
                      });
                      appdata.saveData();
                    },
                    child: Text(
                      "Clear specific reader settings for this device".tl,
                    ),
                  ),
                ).toSliver(),
              SliverToBoxAdapter(child: Divider()),
            ],
          ),
        _SwitchSetting(
          title: "Tap to turn Pages".tl,
          settingKey: "enableTapToTurnPages",
          onChanged: () {
            widget.onChanged?.call("enableTapToTurnPages");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Reverse tap to turn Pages".tl,
          settingKey: "reverseTapToTurnPages",
          onChanged: () {
            widget.onChanged?.call("reverseTapToTurnPages");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Page Up/Down Action".tl,
          settingKey: "pageUpAndDownAction",
          optionTranslation: {
            "chapter": "Switch chapter".tl,
            "page": "Turn page".tl,
            "disabled": "Disabled".tl,
          },
          onChanged: () {
            widget.onChanged?.call("pageUpAndDownAction");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Page animation".tl,
          settingKey: "enablePageAnimation",
          onChanged: () {
            widget.onChanged?.call("enablePageAnimation");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Reading mode".tl,
          settingKey: "readerMode",
          optionTranslation: {
            "galleryLeftToRight": "Gallery (Left to Right)".tl,
            "galleryRightToLeft": "Gallery (Right to Left)".tl,
            "galleryTopToBottom": "Gallery (Top to Bottom)".tl,
            "continuousLeftToRight": "Continuous (Left to Right)".tl,
            "continuousRightToLeft": "Continuous (Right to Left)".tl,
            "continuousTopToBottom": "Continuous (Top to Bottom)".tl,
          },
          onChanged: () {
            setState(() {});
            var readerMode = appdata.settings['readerMode'];
            if (readerMode?.toLowerCase().startsWith('continuous') ?? false) {
              appdata.settings['readerScreenPicNumberForLandscape'] = 1;
              widget.onChanged?.call('readerScreenPicNumberForLandscape');
              appdata.settings['readerScreenPicNumberForPortrait'] = 1;
              widget.onChanged?.call('readerScreenPicNumberForPortrait');
            }
            widget.onChanged?.call("readerMode");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SliderSetting(
          title: "Auto page turning interval".tl,
          settingsIndex: "autoPageTurningInterval",
          interval: 1,
          min: 1,
          max: 20,
          onChanged: () {
            setState(() {});
            widget.onChanged?.call("autoPageTurningInterval");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          // ⭐ C4 修复（审计 AP1-C4 ✓）：可见性判定改用**当前作用域的有效值** ✗→✓ ——
          // 原先直接读**全局** `appdata.settings['readerMode']` ✗：一旦 `readerMode` 被纳入
          // 「漫画 / 设备专属设置」的作用域存储 ✗，这里显示就会与**实际生效值不一致** ✓
          //（本页其它设置项早已统一用 `readSettingValue(...)` ✓）。
          // 注 ✓：`readerMode` 目前**只写全局** ✓ → 本改动**行为等价** ✓（`??` 回退全局保证不为空 ✓）。
          visible:
              (appdata.settings.readSettingValue(
                        key: 'readerMode',
                        comicId: isEnabledSpecificSettings
                            ? widget.comicId
                            : null,
                        comicSource: isEnabledSpecificSettings
                            ? widget.comicSource
                            : null,
                        useDeviceSettings: useDeviceSpecificSettings,
                      ) ??
                      appdata.settings['readerMode'])
                  .toString()
                  .startsWith('gallery'),
          child: _SliderSetting(
            title:
                "The number of pic in screen for landscape (Only Gallery Mode)"
                    .tl,
            settingsIndex: "readerScreenPicNumberForLandscape",
            masked: true,
            interval: 1,
            min: 1,
            max: 5,
            onChanged: () {
              setState(() {});
              widget.onChanged?.call("readerScreenPicNumberForLandscape");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SliverAnimatedVisibility(
          // ⭐ C4 修复（审计 AP1-C4 ✓）：可见性判定改用**当前作用域的有效值** ✗→✓ ——
          // 原先直接读**全局** `appdata.settings['readerMode']` ✗：一旦 `readerMode` 被纳入
          // 「漫画 / 设备专属设置」的作用域存储 ✗，这里显示就会与**实际生效值不一致** ✓
          //（本页其它设置项早已统一用 `readSettingValue(...)` ✓）。
          // 注 ✓：`readerMode` 目前**只写全局** ✓ → 本改动**行为等价** ✓（`??` 回退全局保证不为空 ✓）。
          visible:
              (appdata.settings.readSettingValue(
                        key: 'readerMode',
                        comicId: isEnabledSpecificSettings
                            ? widget.comicId
                            : null,
                        comicSource: isEnabledSpecificSettings
                            ? widget.comicSource
                            : null,
                        useDeviceSettings: useDeviceSpecificSettings,
                      ) ??
                      appdata.settings['readerMode'])
                  .toString()
                  .startsWith('gallery'),
          child: _SliderSetting(
            title:
                "The number of pic in screen for portrait (Only Gallery Mode)"
                    .tl,
            settingsIndex: "readerScreenPicNumberForPortrait",
            masked: true,
            interval: 1,
            min: 1,
            max: 5,
            onChanged: () {
              widget.onChanged?.call("readerScreenPicNumberForPortrait");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SliverAnimatedVisibility(
          // ⭐ 复查修复（2026-10-09 ✓）：**本页还有 2 处漏改的全局读数** ✗ ——
          // C4 当时只把前面两处改成 `readSettingValue(...)` ✓，但可见性判定这里（以及下面"连续模式"
          // 那处 ✓）仍直接读**全局** `appdata.settings['readerMode']` ✗ → 一旦 `readerMode` 被纳入
          // 「漫画 / 设备专属设置」的作用域存储 ✓，**显示就会与生效值不一致** ✓。
          // 现按与 C4 **完全相同的写法**改为作用域有效值 ✓（`??` 回退全局 ✓，`.toString()` 防类型 ✓）。
          // 注 ✓：`readerMode` 目前**只写全局** ✓ → 本改动**行为等价** ✓（作用域扩展后自动正确 ✓）。
          visible:
              (appdata.settings.readSettingValue(
                        key: 'readerMode',
                        comicId: isEnabledSpecificSettings
                            ? widget.comicId
                            : null,
                        comicSource: isEnabledSpecificSettings
                            ? widget.comicSource
                            : null,
                        useDeviceSettings: useDeviceSpecificSettings,
                      ) ??
                      appdata.settings['readerMode'])
                  .toString()
                  .startsWith('gallery') &&
              (appdata.settings['readerScreenPicNumberForLandscape'] > 1 ||
                  appdata.settings['readerScreenPicNumberForPortrait'] > 1),
          child: _SwitchSetting(
            title: "Show single image on first page".tl,
            settingKey: "showSingleImageOnFirstPage",
            masked: true,
            onChanged: () {
              widget.onChanged?.call("showSingleImageOnFirstPage");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        SliverAnimatedVisibility(
          // ⭐ 复查修复（2026-10-09 ✓）：同 C4 —— 改用**作用域有效值** ✓（原为全局读数 ✗，见上一条注释 ✓）。
          visible:
              (appdata.settings.readSettingValue(
                        key: 'readerMode',
                        comicId: isEnabledSpecificSettings
                            ? widget.comicId
                            : null,
                        comicSource: isEnabledSpecificSettings
                            ? widget.comicSource
                            : null,
                        useDeviceSettings: useDeviceSpecificSettings,
                      ) ??
                      appdata.settings['readerMode'])
                  .toString()
                  .startsWith('continuous'),
          child: _SliderSetting(
            title: "Mouse scroll speed".tl,
            settingsIndex: "readerScrollSpeed",
            masked: true,
            interval: 0.1,
            min: 0.5,
            max: 3,
            onChanged: () {
              widget.onChanged?.call("readerScrollSpeed");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        _SwitchSetting(
          title: 'Double tap to zoom'.tl,
          settingKey: 'enableDoubleTapToZoom',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('enableDoubleTapToZoom');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: 'Long press to zoom'.tl,
          settingKey: 'enableLongPressToZoom',
          onChanged: () {
            setState(() {});
            widget.onChanged?.call('enableLongPressToZoom');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          // ⭐ 复查补漏（2026-10-09 ✓，归档复核发现 ✗）：本行原读**全局** `enableLongPressToZoom` ✗ ——
          // 而它上面那个开关（与上方两处**同一族**设置行 ✓、key 一致 ✓）是**带作用域**的 ✓
          //（`comicId` / `comicSource` / `useDeviceSettings` ✓）→ 用户若把该项设为**漫画 / 设备专属** ✓，
          // 开关会亮 ✓ 但**这一行不会出现** ✗ —— 即 C4 修复**漏掉的第 3 处**同类问题 ✓。
          // ⚠️ 注意 ✗：此处**刻意不写出该设置行调用的完整字面量** ✓ —— `test/mask_entry_test.dart` 的正则
          //   是**连注释一起扫**的 ✓（本次就因此把我这条注释误报成"未接入遮罩"✗ 并让测试变红 ✓）；
          //   同理 `tool/appearance_guard.dart` 的"裸透明度"正则也会扫到注释内的字面量 ✓ —— 注释里别写这些模式 ✗。
          // 现按与 C4 **完全相同的写法**改用**作用域有效值** ✓（`??` 回退全局 ✓；该键目前只写全局 ⇒ **行为等价** ✓）。
          visible:
              (appdata.settings.readSettingValue(
                    key: 'enableLongPressToZoom',
                    comicId: isEnabledSpecificSettings ? widget.comicId : null,
                    comicSource: isEnabledSpecificSettings
                        ? widget.comicSource
                        : null,
                    useDeviceSettings: useDeviceSpecificSettings,
                  ) ??
                  appdata.settings['enableLongPressToZoom']) ==
              true,
          child: SelectSetting(
            title: "Long press zoom position".tl,
            settingKey: "longPressZoomPosition",
            masked: true,
            optionTranslation: {
              "press": "Press position".tl,
              "center": "Screen center".tl,
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        _SwitchSetting(
          title: 'Limit image width'.tl,
          subtitle: 'When using Continuous(Top to Bottom) mode'.tl,
          settingKey: 'limitImageWidth',
          onChanged: () {
            widget.onChanged?.call('limitImageWidth');
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        if (App.isAndroid)
          _SwitchSetting(
            title: 'Turn page by volume keys'.tl,
            settingKey: 'enableTurnPageByVolumeKey',
            onChanged: () {
              widget.onChanged?.call('enableTurnPageByVolumeKey');
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ).toSliver(),
        _SwitchSetting(
          title: "Display time & battery info in reader".tl,
          settingKey: "enableClockAndBatteryInfoInReader",
          onChanged: () {
            widget.onChanged?.call("enableClockAndBatteryInfoInReader");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show system status bar".tl,
          settingKey: "showSystemStatusBar",
          onChanged: () {
            widget.onChanged?.call("showSystemStatusBar");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SelectSetting(
          title: "Quick collect image".tl,
          settingKey: "quickCollectImage",
          optionTranslation: {
            "No": "Not enable".tl,
            "DoubleTap": "Double Tap".tl,
            "Swipe": "Swipe".tl,
          },
          onChanged: () {
            widget.onChanged?.call("quickCollectImage");
          },
          help:
              "On the image browsing page, you can quickly collect images by sliding horizontally or vertically according to your reading mode"
                  .tl,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _CallbackSetting(
          title: "Custom Image Processing".tl,
          // ⭐ AO1（同款修法 ✓）：内层 Navigator push ✓（不再用全屏弹层 ✗）
          callback: () =>
              showPopUpWidget(context, const _CustomImageProcessing()),
          actionTitle: "Edit".tl,
        ).toSliver(),
        _SliderSetting(
          title: "Number of images preloaded".tl,
          subtitle: "Higher values use more memory".tl,
          settingsIndex: "preloadImageCount",
          interval: 1,
          min: 1,
          max: 16,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show Page Number".tl,
          settingKey: "showPageNumberInReader",
          onChanged: () {
            widget.onChanged?.call("showPageNumberInReader");
          },
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        _SwitchSetting(
          title: "Show Chapter Comments".tl,
          settingKey: "showChapterComments",
          onChanged: _onShowChapterCommentsChanged,
          comicId: isEnabledSpecificSettings ? widget.comicId : null,
          comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
          useDeviceSettings: useDeviceSpecificSettings,
        ).toSliver(),
        SliverAnimatedVisibility(
          visible: _isChapterCommentsAtEndSupported(),
          child: _SwitchSetting(
            title: "Show Comments at Chapter End".tl,
            settingKey: "showChapterCommentsAtEnd",
            masked: true,
            onChanged: () {
              widget.onChanged?.call("showChapterCommentsAtEnd");
            },
            comicId: isEnabledSpecificSettings ? widget.comicId : null,
            comicSource: isEnabledSpecificSettings ? widget.comicSource : null,
            useDeviceSettings: useDeviceSpecificSettings,
          ),
        ),
        if (comicId == null)
          _SliderSetting(
            title: "Comment font size".tl,
            settingsIndex: "commentFontSize",
            interval: 1,
            min: 12,
            max: 24,
          ).toSliver(),
        if (comicId == null)
          _SwitchSetting(
            title: "Reverse default chapter order".tl,
            settingKey: "reverseChapterOrder",
          ).toSliver(),
      ],
    );
  }
}

class _CustomImageProcessing extends StatefulWidget {
  const _CustomImageProcessing();

  @override
  State<_CustomImageProcessing> createState() => __CustomImageProcessingState();
}

class __CustomImageProcessingState extends State<_CustomImageProcessing> {
  var current = '';

  @override
  void initState() {
    super.initState();
    current = appdata.settings['customImageProcessing'];
  }

  @override
  void dispose() {
    appdata.settings['customImageProcessing'] = current;
    appdata.saveData();
    super.dispose();
  }

  int resetKey = 0;

  @override
  Widget build(BuildContext context) {
    // ⭐ 2026-10-09（用户指示）：自定义图像处理页由全屏 Scaffold 改为弹窗形态（与其它二级页统一）。
    return PopUpWidgetScaffold(
      // ⭐ 2026-10-09：弹窗形态必须传 popupStyle: true（否则有背景体系时表面透明 ⇒ 与下层重叠 ✗）。
      popupStyle: true,
      title: "Custom Image Processing".tl,
      tailing: [
        Button.normal(
          onPressed: () {
            current = defaultCustomImageProcessing;
            appdata.settings['customImageProcessing'] = current;
            resetKey++;
            setState(() {});
          },
          child: Text("Reset".tl),
        ),
      ],
      body: Column(
        children: [
          _SwitchSetting(
            title: "Enable".tl,
            settingKey: "enableCustomImageProcessing",
            masked: true,
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.colorScheme.outlineVariant),
              ),
              child: SizedBox.expand(
                child: CodeEditor(
                  key: ValueKey(resetKey),
                  initialValue: appdata.settings['customImageProcessing'],
                  onChanged: (value) {
                    current = value;
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
