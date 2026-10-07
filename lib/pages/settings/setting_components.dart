part of 'settings_page.dart';

class _SwitchSetting extends StatefulWidget {
  const _SwitchSetting({
    required this.title,
    required this.settingKey,
    this.onChanged,
    this.subtitle,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.masked = false,
  });

  final String title;

  final String settingKey;

  final VoidCallback? onChanged;

  final String? subtitle;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  /// 是否由组件自身补一层遮罩：用于**不经过 `toSliver()`** 的独立设置行
  /// （例如 `SliverAnimatedVisibility` 内部的行）。默认 false，保持零回归。
  final bool masked;

  @override
  State<_SwitchSetting> createState() => _SwitchSettingState();
}

class _SwitchSettingState extends State<_SwitchSetting> {
  @override
  Widget build(BuildContext context) {
    var value = appdata.settings.readSettingValue(
      key: widget.settingKey,
      comicId: widget.comicId,
      comicSource: widget.comicSource,
      useDeviceSettings: widget.useDeviceSettings,
    );

    assert(value is bool);

    final content = ListTile(
      title: Text(widget.title),
      subtitle: widget.subtitle == null ? null : Text(widget.subtitle!),
      trailing: Switch(
        value: value,
        onChanged: (value) {
          setState(() {
            appdata.settings.writeSettingValue(
              key: widget.settingKey,
              value: value,
              comicId: widget.comicId,
              comicSource: widget.comicSource,
              useDeviceSettings: widget.useDeviceSettings,
            );
          });
          appdata.saveData().then((_) {
            widget.onChanged?.call();
          });
        },
      ),
    );
    return maskIfNeeded(widget.masked, content);
  }
}

class SelectSetting extends StatelessWidget {
  const SelectSetting({
    super.key,
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.masked = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  /// 是否由组件自身补一层遮罩：用于**不经过 `toSliver()`** 的独立设置行
  /// （例如 `SliverAnimatedVisibility` 内部的行）。默认 false，保持零回归。
  final bool masked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 450) {
            return _DoubleLineSelectSettings(
              title: title,
              settingKey: settingKey,
              optionTranslation: optionTranslation,
              onChanged: onChanged,
              help: help,
              comicId: comicId,
              comicSource: comicSource,
              useDeviceSettings: useDeviceSettings,
              masked: masked,
            );
          } else {
            return _EndSelectorSelectSetting(
              title: title,
              settingKey: settingKey,
              optionTranslation: optionTranslation,
              onChanged: onChanged,
              help: help,
              comicId: comicId,
              comicSource: comicSource,
              useDeviceSettings: useDeviceSettings,
              masked: masked,
            );
          }
        },
      ),
    );
  }
}

class _DoubleLineSelectSettings extends StatefulWidget {
  const _DoubleLineSelectSettings({
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.masked = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  /// 是否由组件自身补一层遮罩：用于**不经过 `toSliver()`** 的独立设置行
  /// （例如 `SliverAnimatedVisibility` 内部的行）。默认 false，保持零回归。
  final bool masked;

  @override
  State<_DoubleLineSelectSettings> createState() =>
      _DoubleLineSelectSettingsState();
}

class _DoubleLineSelectSettingsState extends State<_DoubleLineSelectSettings> {
  @override
  Widget build(BuildContext context) {
    var value = appdata.settings.readSettingValue(
      key: widget.settingKey,
      comicId: widget.comicId,
      comicSource: widget.comicSource,
      useDeviceSettings: widget.useDeviceSettings,
    );

    final content = ListTile(
      title: Row(
        children: [
          Text(widget.title),
          const SizedBox(width: 4),
          if (widget.help != null)
            Button.icon(
              size: AppIconSize.sm,
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return ContentDialog(
                      title: "Help".tl,
                      content: Text(
                        widget.help!,
                      ).paddingHorizontal(16).fixWidth(double.infinity),
                      actions: [
                        Button.filled(
                          onPressed: context.pop,
                          child: Text("OK".tl),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
      subtitle: Text(widget.optionTranslation[value] ?? "None"),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () {
        var renderBox = context.findRenderObject() as RenderBox;
        var offset = renderBox.localToGlobal(Offset.zero);
        var size = renderBox.size;
        var rect = offset & size;
        showMenu(
          elevation: 3,
          color: context.brightness == Brightness.light
              ? const Color(0xFFF6F6F6)
              : const Color(0xFF1E1E1E),
          context: context,
          position: RelativeRect.fromRect(
            rect,
            Offset.zero & MediaQuery.of(context).size,
          ),
          items: widget.optionTranslation.keys
              .map(
                (key) => PopupMenuItem(
                  value: key,
                  height: App.isMobile ? 46 : 40,
                  child: Text(widget.optionTranslation[key]!),
                ),
              )
              .toList(),
        ).then((value) {
          if (value != null) {
            setState(() {
              appdata.settings.writeSettingValue(
                key: widget.settingKey,
                value: value,
                comicId: widget.comicId,
                comicSource: widget.comicSource,
                useDeviceSettings: widget.useDeviceSettings,
              );
            });
            appdata.saveData();
            widget.onChanged?.call();
          }
        });
      },
    );
    return maskIfNeeded(widget.masked, content);
  }
}

class _EndSelectorSelectSetting extends StatefulWidget {
  const _EndSelectorSelectSetting({
    required this.title,
    required this.settingKey,
    required this.optionTranslation,
    this.onChanged,
    this.help,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.masked = false,
  });

  final String title;

  final String settingKey;

  final Map<String, String> optionTranslation;

  final VoidCallback? onChanged;

  final String? help;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  /// 是否由组件自身补一层遮罩：用于**不经过 `toSliver()`** 的独立设置行
  /// （例如 `SliverAnimatedVisibility` 内部的行）。默认 false，保持零回归。
  final bool masked;

  @override
  State<_EndSelectorSelectSetting> createState() =>
      _EndSelectorSelectSettingState();
}

class _EndSelectorSelectSettingState extends State<_EndSelectorSelectSetting> {
  @override
  Widget build(BuildContext context) {
    var options = widget.optionTranslation;
    var value = appdata.settings.readSettingValue(
      key: widget.settingKey,
      comicId: widget.comicId,
      comicSource: widget.comicSource,
      useDeviceSettings: widget.useDeviceSettings,
    );
    final content = ListTile(
      title: Row(
        children: [
          Text(widget.title),
          const SizedBox(width: 4),
          if (widget.help != null)
            Button.icon(
              size: AppIconSize.sm,
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return ContentDialog(
                      title: "Help".tl,
                      content: Text(
                        widget.help!,
                      ).paddingHorizontal(16).fixWidth(double.infinity),
                      actions: [
                        Button.filled(
                          onPressed: context.pop,
                          child: Text("OK".tl),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
      trailing: Select(
        current: options[value],
        values: options.values.toList(),
        minWidth: 64,
        onTap: (index) {
          setState(() {
            var value = options.keys.elementAt(index);
            appdata.settings.writeSettingValue(
              key: widget.settingKey,
              value: value,
              comicId: widget.comicId,
              comicSource: widget.comicSource,
              useDeviceSettings: widget.useDeviceSettings,
            );
          });
          appdata.saveData();
          widget.onChanged?.call();
        },
      ),
    );
    return maskIfNeeded(widget.masked, content);
  }
}

class _SliderSetting extends StatefulWidget {
  const _SliderSetting({
    required this.title,
    required this.settingsIndex,
    required this.interval,
    required this.min,
    required this.max,
    this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.subtitle,
    this.comicId,
    this.comicSource,
    this.useDeviceSettings = false,
    this.masked = false,
  });

  final String title;

  final String settingsIndex;

  final double interval;

  final double min;

  final double max;

  final VoidCallback? onChanged;

  final void Function(double value)? onChangeStart;

  final VoidCallback? onChangeEnd;

  final String? subtitle;

  final String? comicId;

  final String? comicSource;

  final bool useDeviceSettings;

  /// 是否由组件自身补一层遮罩：用于**不经过 `toSliver()`** 的独立设置行
  /// （例如 `SliverAnimatedVisibility` 内部的行）。默认 false，保持零回归。
  final bool masked;

  @override
  State<_SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<_SliderSetting> {
  double _normalizeValue(double value) {
    final steps = ((value - widget.min) / widget.interval).round();
    final normalized = widget.min + steps * widget.interval;
    return normalized.clamp(widget.min, widget.max).toDouble();
  }

  dynamic _valueForSettings(double value) {
    final normalized = _normalizeValue(value);
    if (normalized.roundToDouble() == normalized) {
      return normalized.round();
    }
    return normalized;
  }

  String _displayValue(double value) {
    final normalized = _normalizeValue(value);
    if (normalized.roundToDouble() == normalized) {
      return normalized.round().toString();
    }
    return normalized
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _setValue(double value) {
    final normalizedValue = _valueForSettings(value);
    // int / double 的写入路径**完全一致**：原先 if (is int) 两份一模一样的分支已合并
    appdata.settings.writeSettingValue(
      key: widget.settingsIndex,
      value: normalizedValue,
      comicId: widget.comicId,
      comicSource: widget.comicSource,
      useDeviceSettings: widget.useDeviceSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    var value = (appdata.settings.readSettingValue(
      key: widget.settingsIndex,
      comicId: widget.comicId,
      comicSource: widget.comicSource,
      useDeviceSettings: widget.useDeviceSettings,
    )).toDouble();
    value = _normalizeValue(value);
    final content = ListTile(
      title: Text(widget.title, softWrap: true, maxLines: 2),
      trailing: Text(_displayValue(value), style: ts.s12),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) Text(widget.subtitle!, style: ts.s12),
          Slider(
            value: value,
            onChanged: (value) {
              setState(() {
                _setValue(value);
              });
              widget.onChanged?.call();
            },
            onChangeStart: (value) {
              widget.onChangeStart?.call(value);
            },
            onChangeEnd: (value) {
              _setValue(value);
              appdata.saveData();
              widget.onChangeEnd?.call();
            },
            divisions: ((widget.max - widget.min) / widget.interval).toInt(),
            min: widget.min,
            max: widget.max,
          ),
        ],
      ),
    );
    return maskIfNeeded(widget.masked, content);
  }
}

class _PopupWindowSetting extends StatelessWidget {
  const _PopupWindowSetting({
    required this.title,
    required this.builder,
    this.enabled = true,
  });

  final Widget Function() builder;

  final String title;

  /// 为 false 时该项置灰且不可点击进入。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(title),
      trailing: const Icon(Icons.arrow_right),
      onTap: enabled
          ? () {
              showPopUpWidget(App.rootContext, builder());
            }
          : null,
    );
  }
}

class _MultiPagesFilter extends StatefulWidget {
  const _MultiPagesFilter({
    required this.title,
    required this.settingsIndex,
    required this.pages,
    this.masked = false,
  });

  final String title;

  final String settingsIndex;

  // key - name
  final Map<String, String> pages;

  /// 是否由组件自身补一层遮罩：本组件**只在弹层里渲染**（`_PopupWindowSetting`
  /// 的 builder 或 `showPopUpWidget`），弹层里的每一行都需要单独接遮罩。
  final bool masked;

  @override
  State<_MultiPagesFilter> createState() => _MultiPagesFilterState();
}

class _MultiPagesFilterState extends State<_MultiPagesFilter> {
  late List<String> keys;

  @override
  void initState() {
    keys = List.from(appdata.settings[widget.settingsIndex]);
    keys.remove("");
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    Future.microtask(() {
      updateSetting();
    });
  }

  var reorderWidgetKey = UniqueKey();
  var scrollController = ScrollController();
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    var tiles = keys.map((e) => buildItem(e)).toList();

    var view = ReorderableBuilder<String>(
      key: reorderWidgetKey,
      scrollController: scrollController,
      longPressDelay: App.isDesktop
          ? const Duration(milliseconds: 100)
          : const Duration(milliseconds: 500),
      dragChildBoxDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 5,
            offset: Offset(0, 2),
            spreadRadius: 2,
          ),
        ],
      ),
      onReorder: (reorderFunc) {
        setState(() {
          keys = List.from(reorderFunc(keys));
        });
      },
      children: tiles,
      builder: (children) {
        return GridView(
          key: _key,
          controller: scrollController,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            mainAxisExtent: 48,
          ),
          children: children,
        );
      },
    );

    return PopUpWidgetScaffold(
      title: widget.title,
      tailing: [
        if (keys.length < widget.pages.length)
          TextButton.icon(
            label: Text("Add".tl),
            icon: const Icon(Icons.add),
            onPressed: showAddDialog,
          ),
      ],
      body: view,
    );
  }

  Widget buildItem(String key) {
    Widget removeButton = Padding(
      padding: const EdgeInsets.only(right: AppSpace.sm),
      child: IconButton(
        onPressed: () {
          setState(() {
            keys.remove(key);
          });
        },
        icon: const Icon(Icons.delete_outline),
      ),
    );

    final content = ListTile(
      title: Text(widget.pages[key] ?? "(Invalid) $key"),
      key: Key(key),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [removeButton, const Icon(Icons.drag_handle)],
      ),
    );
    return maskIfNeeded(widget.masked, content);
  }

  void showAddDialog() {
    var canAdd = <String, String>{};
    widget.pages.forEach((key, value) {
      if (!keys.contains(key)) {
        canAdd[key] = value;
      }
    });
    var selected = <String>[];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return ContentDialog(
              title: "Add".tl,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: canAdd.entries
                    .map(
                      (e) => CheckboxListTile(
                        value: selected.contains(e.key),
                        title: Text(e.value),
                        key: Key(e.key),
                        onChanged: (value) {
                          setState(() {
                            if (value!) {
                              selected.add(e.key);
                            } else {
                              selected.remove(e.key);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              actions: [
                if (selected.length < canAdd.length)
                  TextButton(
                    child: Text("Select All".tl),
                    onPressed: () {
                      setState(() {
                        selected = canAdd.keys.toList();
                      });
                    },
                  )
                else
                  TextButton(
                    child: Text("Deselect All".tl),
                    onPressed: () {
                      setState(() {
                        selected.clear();
                      });
                    },
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: selected.isNotEmpty
                      ? () {
                          this.setState(() {
                            keys.addAll(selected);
                          });
                          Navigator.pop(context);
                        }
                      : null,
                  child: Text("Add".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void updateSetting() {
    appdata.settings[widget.settingsIndex] = keys;
    appdata.saveData();
  }
}

class _CallbackSetting extends StatelessWidget {
  const _CallbackSetting({
    required this.title,
    required this.callback,
    required this.actionTitle,
  });

  final String title;

  final VoidCallback callback;

  final String actionTitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Button.normal(
        onPressed: callback,
        child: Text(actionTitle),
      ).fixHeight(28),
      onTap: callback,
    );
  }
}

class _SettingPartTitle extends StatelessWidget {
  const _SettingPartTitle({required this.title, required this.icon});

  final String title;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.only(
          left: AppSpace.lg,
          top: AppSpace.lg,
          bottom: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: context.colorScheme.onSurface.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.lg),
            const SizedBox(width: 8),
            Text(title, style: ts.s18),
          ],
        ),
      ),
    );
  }
}
