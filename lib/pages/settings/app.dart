part of 'settings_page.dart';

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});

  @override
  State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  int _previousRetentionDays = 0;

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("App".tl)),
        _SettingPartTitle(title: "Data".tl, icon: Icons.storage),
        _SettingPartTitle(title: "下载路径".tl, icon: Icons.folder_outlined),
        ListTile(
          title: Text("本地下载路径".tl),
          subtitle: Text(LocalManager().path, softWrap: false),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: LocalManager().path));
              context.showMessage(message: "Path copied to clipboard".tl);
            },
          ),
        ).toSliver(),
        _CallbackSetting(
          title: "设置本地下载路径".tl,
          actionTitle: "Set".tl,
          callback: () async {
            showDialog(
              context: context,
              builder: (ctx) => _LocalPathDialog(
                onPathSet: () => setState(() {}),
              ),
            );
          },
        ).toSliver(),
        ListTile(
          title: Text("NAS 下载路径 (SMB)".tl),
          subtitle: Text(LocalManager().smbPath, softWrap: false),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: LocalManager().smbPath));
              context.showMessage(message: "Path copied to clipboard".tl);
            },
          ),
        ).toSliver(),
        _CallbackSetting(
          title: "设置 NAS 下载路径".tl,
          actionTitle: "Set".tl,
          callback: () async {
            showDialog(
              context: context,
              builder: (ctx) => _NasPathDialog(
                onPathSet: () => setState(() {}),
              ),
            );
          },
        ).toSliver(),
        ListTile(
          title: Text("Cache Size".tl),
          subtitle: Text(bytesToReadableString(CacheManager().currentSize)),
        ).toSliver(),
        _CallbackSetting(
          title: "Clear Cache".tl,
          actionTitle: "Clear".tl,
          callback: () async {
            var loadingDialog = showLoadingDialog(
              App.rootContext,
              barrierDismissible: false,
              allowCancel: false,
            );
            await CacheManager().clear();
            loadingDialog.close();
            if (!context.mounted) return;
            context.showMessage(message: "Cache cleared".tl);
            setState(() {});
          },
        ).toSliver(),
        _SliderSetting(
          title: "Cache Limit".tl,
          settingsIndex: "cacheSize",
          interval: 256,
          min: 256,
          max: 8192,
          onChanged: () {
            CacheManager().setLimitSize(appdata.settings['cacheSize']);
          },
        ).toSliver(),
        _SliderSetting(
          title: "Auto Clear History".tl,
          subtitle: "0 means disabled".tl,
          settingsIndex: "historyRetentionDays",
          interval: 7,
          min: 0,
          max: 182,
          onChangeStart: (value) {
            _previousRetentionDays =
                (appdata.settings['historyRetentionDays'] as num).round();
          },
          onChangeEnd: () {
            final retentionDays =
                (appdata.settings['historyRetentionDays'] as num).round();
            const confirmThreshold = 15;
            if (retentionDays > 0 &&
                retentionDays <= confirmThreshold &&
                retentionDays < _previousRetentionDays) {
              var confirmed = false;
              showConfirmDialog(
                context: App.rootContext,
                title: "Auto Clear History".tl,
                content: "Short retention warning".tl,
                confirmText: "Confirm",
                btnColor: context.colorScheme.error,
                onConfirm: () {
                  confirmed = true;
                  HistoryManager().clearExpiredHistory(retentionDays);
                },
              ).then((_) {
                if (!confirmed) {
                  appdata.settings['historyRetentionDays'] =
                      _previousRetentionDays;
                  appdata.saveData();
                  if (mounted) {
                    setState(() {});
                  }
                }
              });
              return;
            }
            if (retentionDays > 0) {
              HistoryManager().clearExpiredHistory(retentionDays);
            }
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Export App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            var file = await exportAppData(false);
            await saveFile(filename: "data.venera", file: file);
            controller.close();
          },
          actionTitle: 'Export'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Import App Data".tl,
          callback: () async {
            var controller = showLoadingDialog(context);
            var file = await selectFile(ext: ['venera', 'picadata']);
            if (file != null) {
              var cacheFile = File(
                FilePath.join(App.cachePath, "import_data_temp"),
              );
              await file.saveTo(cacheFile.path);
              try {
                if (file.name.endsWith('picadata')) {
                  await importPicaData(cacheFile);
                } else {
                  await importAppData(cacheFile, isLocalRestore: true);
                }
              } catch (e, s) {
                Log.error("Import data", e.toString(), s);
                if (!context.mounted) return;
                context.showMessage(message: "Failed to import data".tl);
              } finally {
                cacheFile.deleteIgnoreError();
                App.forceRebuild();
              }
            }
            controller.close();
          },
          actionTitle: 'Import'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Data Sync".tl,
          callback: () async {
            showPopUpWidget(context, const _WebdavSetting());
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _CallbackSetting(
          title: "Comic Archive Backup".tl,
          callback: () async {
            showPopUpWidget(context, const _BackupWebdavSetting());
          },
          actionTitle: 'Set'.tl,
        ).toSliver(),
        _SettingPartTitle(title: "User".tl, icon: Icons.person_outline),
        SelectSetting(
          title: "Language".tl,
          settingKey: "language",
          optionTranslation: const {
            "system": "System",
            "zh-CN": "简体中文",
            "zh-TW": "繁體中文",
            "en-US": "English",
          },
          onChanged: () {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Initial Page".tl,
          settingKey: "initialPage",
          optionTranslation: {
            '0': "Home Page".tl,
            '1': "Favorites Page".tl,
            '2': "Explore Page".tl,
            '3': "Categories Page".tl,
          },
        ).toSliver(),
        if (!App.isLinux)
          _SwitchSetting(
            title: "Authorization Required".tl,
            settingKey: "authorizationRequired",
            onChanged: () async {
              var current = appdata.settings['authorizationRequired'];
              if (current) {
                final auth = LocalAuthentication();
                bool canAuthenticate;
                try {
                  final bool canAuthenticateWithBiometrics =
                      await auth.canCheckBiometrics;
                  canAuthenticate =
                      canAuthenticateWithBiometrics ||
                      await auth.isDeviceSupported();
                } catch (_) {
                  canAuthenticate = false;
                }
                if (!canAuthenticate) {
                  if (!context.mounted) return;
                  await showPopUpWidget(context, const AuthPinSetting());
                  if (!context.mounted) return;
                  if (AuthStorage.pinHash == null) {
                    setState(() {
                      appdata.settings['authorizationRequired'] = false;
                    });
                    appdata.saveData();
                  }
                }
              }
              if (mounted) setState(() {});
            },
          ).toSliver(),
        if (!App.isLinux && appdata.settings['authorizationRequired'] == true)
          _CallbackSetting(
            title: "Use PIN to unlock".tl,
            actionTitle: AuthStorage.pinHash == null ? "Set".tl : "Change".tl,
            callback: () async {
              await showPopUpWidget(context, const AuthPinSetting());
              if (mounted) setState(() {});
            },
          ).toSliver(),
        SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String logLevelToShow = "all";

  @override
  Widget build(BuildContext context) {
    var logToShow = logLevelToShow == "all"
        ? Log.logs
        : Log.logs.where((log) => log.level.name == logLevelToShow).toList();
    return Scaffold(
      appBar: Appbar(
        title: Text("Logs".tl),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("all"),
                    onTap: () => setState(() => logLevelToShow = "all"),
                  ),
                  PopupMenuItem(
                    child: Text("info"),
                    onTap: () => setState(() => logLevelToShow = "info"),
                  ),
                  PopupMenuItem(
                    child: Text("warning"),
                    onTap: () => setState(() => logLevelToShow = "warning"),
                  ),
                  PopupMenuItem(
                    child: Text("error"),
                    onTap: () => setState(() => logLevelToShow = "error"),
                  ),
                ],
              );
            }),
            icon: const Icon(Icons.filter_list_outlined),
          ),
          IconButton(
            onPressed: () => setState(() {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("Clear".tl),
                    onTap: () => setState(() => Log.clear()),
                  ),
                  PopupMenuItem(
                    child: Text("Disable Length Limitation".tl),
                    onTap: () {
                      Log.ignoreLimitation = true;
                      context.showMessage(
                        message: "Only valid for this run".tl,
                      );
                    },
                  ),
                  PopupMenuItem(
                    child: Text("Export".tl),
                    onTap: () => saveLog(Log().toString()),
                  ),
                ],
              );
            }),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        controller: ScrollController(),
        itemCount: logToShow.length,
        itemBuilder: (context, index) {
          index = logToShow.length - index - 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(logToShow[index].title),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Container(
                        decoration: BoxDecoration(
                          color: [
                            Theme.of(context).colorScheme.error,
                            Theme.of(context).colorScheme.errorContainer,
                            Theme.of(context).colorScheme.primaryContainer,
                          ][logToShow[index].level.index],
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logToShow[index].level.name,
                            style: TextStyle(
                              color: logToShow[index].level.index == 0
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(logToShow[index].content),
                  Text(
                    logToShow[index].time.toString().replaceAll(
                      RegExp(r"\.\w+"),
                      "",
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: logToShow[index].content),
                      );
                    },
                    child: Text("Copy".tl),
                  ),
                  const Divider(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void saveLog(String log) async {
    saveFile(data: utf8.encode(log), filename: 'log.txt');
  }
}

class _WebdavSetting extends StatefulWidget {
  const _WebdavSetting();

  @override
  State<_WebdavSetting> createState() => _WebdavSettingState();
}

class _WebdavSettingState extends State<_WebdavSetting> {
  String url = "";
  String user = "";
  String pass = "";

  bool autoSync = true;

  bool isTesting = false;
  bool upload = true;

  @override
  void initState() {
    super.initState();
    if (appdata.settings['webdav'] is! List) {
      appdata.settings['webdav'] = [];
    }
    var configs = appdata.settings['webdav'] as List;
    if (configs.whereType<String>().length != 3) {
      return;
    }
    url = configs[0];
    user = configs[1];
    pass = configs[2];
    autoSync = appdata.implicitData['webdavAutoSync'] ?? true;
  }

  void onAutoSyncChanged(bool value) {
    setState(() {
      autoSync = value;
      appdata.implicitData['webdavAutoSync'] = value;
      appdata.writeImplicitData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Webdav",
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "URL",
                hintText: "A valid WebDav directory URL".tl,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: url),
              onChanged: (value) => url = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
              controller: TextEditingController(text: user),
              onChanged: (value) => user = value,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
              controller: TextEditingController(text: pass),
              onChanged: (value) => pass = value,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.sync),
              title: Text("Auto Sync Data".tl),
              contentPadding: EdgeInsets.zero,
              trailing: Switch(value: autoSync, onChanged: onAutoSyncChanged),
            ),
            const SizedBox(height: 12),
            RadioGroup<bool>(
              groupValue: upload,
              onChanged: (value) {
                setState(() {
                  upload = value ?? upload;
                });
              },
              child: Row(
                children: [
                  Text("Operation".tl),
                  Radio<bool>(value: true),
                  Text("Upload".tl),
                  Radio<bool>(value: false),
                  Text("Download".tl),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: autoSync
                  ? Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Once the operation is successful, app will automatically sync data with the server."
                                  .tl,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Button.outlined(
                    isLoading: isTesting,
                    onPressed: testConnection,
                    child: Text("Test Connection".tl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Button.filled(
                    isLoading: isTesting,
                    onPressed: () async {
                      if (isTesting) return;
                      var oldConfig = appdata.settings['webdav'];
                      var oldAutoSync = appdata.implicitData['webdavAutoSync'];

                      if (url.trim().isEmpty &&
                          user.trim().isEmpty &&
                          pass.trim().isEmpty) {
                        appdata.settings['webdav'] = [];
                        appdata.implicitData['webdavAutoSync'] = false;
                        appdata.writeImplicitData();
                        appdata.saveData();
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                        return;
                      }

                      appdata.settings['webdav'] = [url, user, pass];
                      appdata.implicitData['webdavAutoSync'] = autoSync;
                      appdata.writeImplicitData();

                      if (!autoSync) {
                        appdata.saveData();
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                        return;
                      }

                      setState(() {
                        isTesting = true;
                      });
                      var testResult = upload
                          ? await DataSync().uploadData()
                          : await DataSync().downloadData();
                      if (!mounted) return;
                      setState(() {
                        isTesting = false;
                      });
                      if (testResult.error) {
                        appdata.settings['webdav'] = oldConfig;
                        appdata.implicitData['webdavAutoSync'] = oldAutoSync;
                        appdata.writeImplicitData();
                        appdata.saveData();
                        if (!context.mounted) return;
                        context.showMessage(message: testResult.errorMessage!);
                        context.showMessage(message: "Saved Failed".tl);
                      } else {
                        appdata.saveData();
                        if (!context.mounted) return;
                        context.showMessage(message: "Saved".tl);
                        App.rootPop();
                      }
                    },
                    child: Text("Continue".tl),
                  ),
                ),
              ],
            ),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }

  Future<void> testConnection() async {
    if (isTesting) return;
    setState(() {
      isTesting = true;
    });
    final result = await DataSync().testConnection([url, user, pass]);
    if (!mounted) return;
    setState(() {
      isTesting = false;
    });
    if (result.error) {
      context.showMessage(message: result.errorMessage!);
    } else {
      context.showMessage(message: "Connection successful".tl);
    }
  }
}

class _BackupWebdavSetting extends StatefulWidget {
  const _BackupWebdavSetting();

  @override
  State<_BackupWebdavSetting> createState() => _BackupWebdavSettingState();
}

class _BackupWebdavSettingState extends State<_BackupWebdavSetting> {
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _remotePathController;
  bool syncEnabled = false;
  bool isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = BackupConfig.fromSettings();
    _urlController = TextEditingController(text: config.url);
    _userController = TextEditingController(text: config.user);
    _passController = TextEditingController(text: config.pass);
    _remotePathController = TextEditingController(text: config.remotePath);
    syncEnabled = appdata.settings['backupWebdavSyncEnabled'] == true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _remotePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Comic Archive Backup".tl,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "URL",
                hintText: "A valid WebDav directory URL".tl,
                border: OutlineInputBorder(),
              ),
              controller: _urlController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _userController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _passController,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Remote Path".tl,
                hintText: "/venera_backup/",
                border: const OutlineInputBorder(),
              ),
              controller: _remotePathController,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "This is only used for CBZ archive backup and restore."
                          .tl,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.sync),
              title: Text("Sync archive config".tl),
              subtitle: Text(
                "Sync archive WebDAV URL, username, password and remote path with app data."
                    .tl,
              ),
              trailing: Switch(
                value: syncEnabled,
                onChanged: (v) {
                  setState(() {
                    syncEnabled = v;
                  });
                },
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Button.outlined(
                    isLoading: isTesting,
                    onPressed: testConnection,
                    child: Text("Test Connection".tl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Button.filled(
                    isLoading: isTesting,
                    onPressed: save,
                    child: Text("Continue".tl),
                  ),
                ),
              ],
            ),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }

  BackupConfig get currentConfig => BackupConfig(
    url: _urlController.text,
    user: _userController.text,
    pass: _passController.text,
    remotePath: _remotePathController.text,
  );

  Future<void> testConnection() async {
    if (isTesting) return;
    setState(() {
      isTesting = true;
    });
    final result = await ComicBackupManager.testConnection(currentConfig);
    if (!mounted) return;
    setState(() {
      isTesting = false;
    });
    if (result.error) {
      context.showMessage(message: result.errorMessage!);
    } else {
      context.showMessage(message: "Connection successful".tl);
    }
  }

  Future<void> save() async {
    if (isTesting) return;
    appdata.settings['backupWebdavSyncEnabled'] = syncEnabled;
    final config = currentConfig;
    if (!config.isValid && config.user.trim().isEmpty && config.pass.isEmpty) {
      await BackupConfig.saveToSettings(config);
      if (!mounted) return;
      context.showMessage(message: "Saved".tl);
      App.rootPop();
      return;
    }
    setState(() {
      isTesting = true;
    });
    final result = await ComicBackupManager.testConnection(config);
    if (!mounted) return;
    setState(() {
      isTesting = false;
    });
    if (result.error) {
      context.showMessage(message: result.errorMessage!);
      context.showMessage(message: "Saved Failed".tl);
    } else {
      await BackupConfig.saveToSettings(config);
      if (!mounted) return;
      context.showMessage(message: "Saved".tl);
      App.rootPop();
    }
  }
}

class _LocalPathDialog extends StatefulWidget {
  final VoidCallback onPathSet;

  const _LocalPathDialog({required this.onPathSet});

  @override
  State<_LocalPathDialog> createState() => _LocalPathDialogState();
}

class _LocalPathDialogState extends State<_LocalPathDialog> {
  final _urlController = TextEditingController();
  bool _isBusy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _browseLocal() async {
    String? result;
    if (App.isAndroid) {
      var picker = DirectoryPicker();
      result = (await picker.pickDirectory())?.path;
    } else if (App.isIOS) {
      result = await selectDirectoryIOS();
    } else {
      result = await selectDirectory();
    }
    if (result == null) return;
    await _setLocalPath(result);
  }

  Future<void> _setLocalPath(String newPath) async {
    if (_isBusy) return;
    if (!App.rootContext.mounted) return;

    setState(() => _isBusy = true);
    var loadingDialog = showLoadingDialog(
      App.rootContext,
      barrierDismissible: false,
      allowCancel: false,
    );

    var res = await LocalManager().setNewPath(newPath);
    if (!App.rootContext.mounted) return;
    loadingDialog.close();
    setState(() => _isBusy = false);
    if (res != null) {
      if (!mounted) return;
      context.showMessage(message: res);
    } else {
      if (!mounted) return;
      context.showMessage(message: "路径设置成功".tl);
      widget.onPathSet();
      Navigator.of(context).pop();
    }
  }

  void _useManualPath() {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      context.showMessage(message: "请输入路径".tl);
      return;
    }
    _setLocalPath(text);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "设置本地下载路径".tl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "选择一个本地文件夹用于保存下载的漫画。该文件夹必须为空。"
                .tl,
          ).paddingHorizontal(16),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Button.outlined(
              isLoading: _isBusy,
              onPressed: _browseLocal,
              child: Text("浏览本地文件夹".tl),
            ),
          ).paddingHorizontal(16),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text("- 或手动输入 -".tl),
              ),
            ],
          ).paddingHorizontal(16),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: "本地路径".tl,
              hintText: "C:\\Comics\\Downloads",
              border: const OutlineInputBorder(),
            ),
            controller: _urlController,
          ).paddingHorizontal(16),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Button.outlined(
              isLoading: _isBusy,
              onPressed: _useManualPath,
              child: Text("使用此路径".tl),
            ),
          ).paddingHorizontal(16),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: Text("Cancel".tl),
        ),
      ],
    );
  }
}

class _NasPathDialog extends StatefulWidget {
  final VoidCallback onPathSet;

  const _NasPathDialog({required this.onPathSet});

  @override
  State<_NasPathDialog> createState() => _NasPathDialogState();
}

class _NasPathDialogState extends State<_NasPathDialog> {
  final _urlController = TextEditingController();
  bool _isBusy = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _setNasPath(String nasUrl) async {
    if (_isBusy) return;
    if (!nasUrl.startsWith('smb://')) {
      context.showMessage(message: "请输入有效的 SMB 地址 (smb://...)".tl);
      return;
    }
    if (!App.rootContext.mounted) return;

    setState(() => _isBusy = true);
    var loadingDialog = showLoadingDialog(
      App.rootContext,
      barrierDismissible: false,
      allowCancel: false,
    );

    appdata.settings['smbDownloadPath'] = nasUrl;
    await appdata.saveData();
    LocalManager().smbPath = nasUrl;

    if (!App.rootContext.mounted) return;
    loadingDialog.close();
    if (!mounted) return;
    context.showMessage(message: "NAS 路径设置成功".tl);
    widget.onPathSet();
    Navigator.of(context).pop();
    setState(() => _isBusy = false);
  }

  void _useManualUrl() {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      context.showMessage(message: "请输入路径".tl);
      return;
    }
    _setNasPath(text);
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: "设置 NAS 下载路径".tl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "输入 SMB/NAS 地址，选择 NAS 下载模式时漫画将保存到此路径。"
                .tl,
          ).paddingHorizontal(16),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              labelText: "SMB 地址".tl,
              hintText: "smb://192.168.1.100/Comics/Downloads",
              border: const OutlineInputBorder(),
            ),
            controller: _urlController,
          ).paddingHorizontal(16),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Button.outlined(
              isLoading: _isBusy,
              onPressed: _useManualUrl,
              child: Text("设置 NAS 路径".tl),
            ),
          ).paddingHorizontal(16),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: Text("Cancel".tl),
        ),
      ],
    );
  }
}