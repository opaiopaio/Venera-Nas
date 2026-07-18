part of 'settings_page.dart';

class NetworkSettings extends StatefulWidget {
  const NetworkSettings({super.key});

  @override
  State<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<NetworkSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Network".tl)),
        _SettingPartTitle(title: "SMB / NAS".tl, icon: Icons.dns_outlined),
        _CallbackSetting(
          title: "SMB / NAS Servers".tl,
          callback: () async {
            showPopUpWidget(context, const _SmbServerManager());
          },
          actionTitle: 'Manage'.tl,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Proxy".tl,
          builder: () => const _ProxySettingView(),
        ).toSliver(),
        _SwitchSetting(
          title: "WebDAV Proxy".tl,
          settingKey: 'webdavProxyEnabled',
        ).toSliver(),
        _PopupWindowSetting(
          title: "DNS Overrides".tl,
          builder: () => const _DNSOverrides(),
        ).toSliver(),
        _SliderSetting(
          title: "Download Threads".tl,
          settingsIndex: 'downloadThreads',
          interval: 1,
          min: 1,
          max: 16,
        ).toSliver(),
      ],
    );
  }
}

class _ProxySettingView extends StatefulWidget {
  const _ProxySettingView();

  @override
  State<_ProxySettingView> createState() => _ProxySettingViewState();
}

class _ProxySettingViewState extends State<_ProxySettingView> {
  String type = '';
  String host = '';
  String port = '';
  String username = '';
  String password = '';

  // USERNAME:PASSWORD@HOST:PORT
  String toProxyStr() {
    if (type == 'direct') {
      return 'direct';
    } else if (type == 'system') {
      return 'system';
    }
    var res = '';
    if (username.isNotEmpty) {
      res += username;
      if (password.isNotEmpty) {
        res += ':$password';
      }
      res += '@';
    }
    res += host;
    if (port.isNotEmpty) {
      res += ':$port';
    }
    return res;
  }

  void parseProxyString(String proxy) {
    if (proxy == 'direct') {
      type = 'direct';
      return;
    } else if (proxy == 'system') {
      type = 'system';
      return;
    }
    type = 'manual';
    var parts = proxy.split('@');
    if (parts.length == 2) {
      var auth = parts[0].split(':');
      if (auth.length == 2) {
        username = auth[0];
        password = auth[1];
      }
      parts = parts[1].split(':');
      if (parts.length == 2) {
        host = parts[0];
        port = parts[1];
      }
    } else {
      parts = proxy.split(':');
      if (parts.length == 2) {
        host = parts[0];
        port = parts[1];
      }
    }
  }

  @override
  void initState() {
    var proxy = appdata.settings['proxy'];
    parseProxyString(proxy);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "Proxy".tl,
      body: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: type,
          onChanged: (v) {
            setState(() {
              type = v ?? type;
            });
            if (type != 'manual') {
              appdata.settings['proxy'] = toProxyStr();
              appdata.saveData();
            }
          },
          child: Column(
            children: [
              RadioListTile<String>(title: Text("Direct".tl), value: 'direct'),
              RadioListTile<String>(title: Text("System".tl), value: 'system'),
              RadioListTile(title: Text("Manual".tl), value: 'manual'),
              if (type == 'manual') buildManualProxy(),
            ],
          ),
        ),
      ),
    );
  }

  var formKey = GlobalKey<FormState>();

  Widget buildManualProxy() {
    return Form(
      key: formKey,
      child: Column(
        children: [
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Host".tl,
            ),
            controller: TextEditingController(text: host),
            onChanged: (v) {
              host = v;
            },
            validator: (v) {
              if (v?.isEmpty ?? false) {
                return "Host cannot be empty".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Port".tl,
            ),
            controller: TextEditingController(text: port),
            onChanged: (v) {
              port = v;
            },
            validator: (v) {
              if (v?.isEmpty ?? true) {
                return null;
              }
              if (int.tryParse(v!) == null) {
                return "Port must be a number".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Username".tl,
            ),
            controller: TextEditingController(text: username),
            onChanged: (v) {
              username = v;
            },
            validator: (v) {
              if ((v?.isEmpty ?? false) && password.isNotEmpty) {
                return "Username cannot be empty".tl;
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: "Password".tl,
            ),
            controller: TextEditingController(text: password),
            onChanged: (v) {
              password = v;
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                appdata.settings['proxy'] = toProxyStr();
                appdata.saveData();
                App.rootContext.pop();
              }
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    ).paddingHorizontal(16).paddingTop(16);
  }
}

class _DNSOverrides extends StatefulWidget {
  const _DNSOverrides();

  @override
  State<_DNSOverrides> createState() => __DNSOverridesState();
}

class __DNSOverridesState extends State<_DNSOverrides> {
  var overrides = <(TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    for (var entry in (appdata.settings['dnsOverrides'] as Map).entries) {
      if (entry.key is String && entry.value is String) {
        overrides.add((
          TextEditingController(text: entry.key),
          TextEditingController(text: entry.value),
        ));
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    for (var entry in overrides) {
      entry.$1.dispose();
      entry.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    var map = <String, String>{};
    for (var entry in overrides) {
      if (entry.$1.text.isNotEmpty && entry.$2.text.isNotEmpty) {
        map[entry.$1.text] = entry.$2.text;
      }
    }
    appdata.settings['dnsOverrides'] = map;
    await appdata.saveData();
    JsEngine().resetDio();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: "DNS Overrides".tl,
      tailing: [
        TextButton.icon(
          onPressed: () async {
            await _save();
            if (context.mounted) {
              context.pop();
            }
          },
          icon: const Icon(Icons.save),
          label: Text("Save".tl),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SwitchSetting(
              title: "Enable DNS Overrides".tl,
              settingKey: "enableDnsOverrides",
            ),
            _SwitchSetting(title: "Server Name Indication", settingKey: "sni"),
            const SizedBox(height: 8),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 8),
              color: context.colorScheme.outlineVariant,
            ),
            for (var i = 0; i < overrides.length; i++) buildOverride(i),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  overrides.add((
                    TextEditingController(),
                    TextEditingController(),
                  ));
                });
              },
              icon: const Icon(Icons.add),
              label: Text("Add".tl),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildOverride(int index) {
    var entry = overrides[index];
    return Container(
      key: ValueKey(index),
      height: 48,
      margin: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.colorScheme.outlineVariant),
          left: BorderSide(color: context.colorScheme.outlineVariant),
          right: BorderSide(color: context.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "Domain".tl,
              ),
              controller: entry.$1,
            ).paddingHorizontal(8),
          ),
          Container(width: 1, color: context.colorScheme.outlineVariant),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: "IP".tl,
              ),
              controller: entry.$2,
            ).paddingHorizontal(8),
          ),
          Container(width: 1, color: context.colorScheme.outlineVariant),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              var removed = overrides.removeAt(index);
              removed.$1.dispose();
              removed.$2.dispose();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class _SmbServerManager extends StatefulWidget {
  const _SmbServerManager();

  @override
  State<_SmbServerManager> createState() => _SmbServerManagerState();
}

class _SmbServerManagerState extends State<_SmbServerManager> {
  List<SmbConnection> get servers {
    final raw = appdata.settings['smbServers'];
    if (raw is! List) return [];
    try {
      return raw
          .map((e) =>
              SmbConnection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  set servers(List<SmbConnection> value) {
    appdata.settings['smbServers'] =
        value.map((e) => e.toJson()).toList();
    appdata.saveData();
  }

  void _addServer() async {
    final result = await showPopUpWidget<bool?>(
      context,
      _SmbServerEditDialog(),
    );
    if (result != false && mounted) {
      setState(() {});
    }
  }

  void _editServer(int index) async {
    final result = await showPopUpWidget<bool?>(
      context,
      _SmbServerEditDialog(connection: servers[index]),
    );
    if (result != false && mounted) {
      setState(() {});
    }
  }

  void _deleteServer(int index) {
    final list = servers;
    list.removeAt(index);
    servers = list;
    setState(() {});
  }

  Future<void> _testServer(int index) async {
    final connection = servers[index];
    setState(() {}); // trigger rebuild for loading indicator if needed
    final error = await connection.testConnection();
    if (!mounted) return;
    if (error == null) {
      showDialogMessage(context, "Test Connection".tl, "Connection successful".tl);
    } else {
      showDialogMessage(context, "Test Connection".tl, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = servers;

    return PopUpWidgetScaffold(
      title: "SMB / NAS Servers".tl,
      body: Column(
        children: [
          if (list.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  "No servers configured".tl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final server = list[index];
                  return ListTile(
                    leading: const Icon(Icons.dns),
                    title: Text(server.name),
                    subtitle: Text(
                      '${server.config.host}/${server.config.share}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.wifi_find),
                          tooltip: "Test Connection".tl,
                          onPressed: () => _testServer(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Edit".tl,
                          onPressed: () => _editServer(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: "Delete".tl,
                          onPressed: () => _deleteServer(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: Button.filled(
                onPressed: _addServer,
                child: Text("Add Server".tl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding / editing an SMB server connection.
class _SmbServerEditDialog extends StatefulWidget {
  final SmbConnection? connection;

  const _SmbServerEditDialog({this.connection});

  @override
  State<_SmbServerEditDialog> createState() => _SmbServerEditDialogState();
}

class _SmbServerEditDialogState extends State<_SmbServerEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _shareController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _domainController;

  bool _isTesting = false;

  bool get _isEditing => widget.connection != null;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _nameController = TextEditingController(text: c?.name ?? '');
    _hostController = TextEditingController(text: c?.config.host ?? '');
    _portController = TextEditingController(
      text: (c?.config.port ?? 445).toString(),
    );
    _shareController = TextEditingController(text: c?.config.share ?? '');
    _usernameController = TextEditingController(
      text: c?.config.username ?? '',
    );
    _passwordController = TextEditingController(
      text: c?.config.password ?? '',
    );
    _domainController = TextEditingController(
      text: c?.config.domain ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _shareController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  SmbConnection _buildConnection() {
    final port = int.tryParse(_portController.text.trim()) ?? 445;
    return SmbConnection(
      name: _nameController.text.trim(),
      config: SmbConfig(
        host: _hostController.text.trim(),
        port: port,
        share: _shareController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        domain: _domainController.text.trim(),
      ),
    );
  }

  Future<void> _test() async {
    if (_isTesting) return;
    setState(() => _isTesting = true);
    final error = await _buildConnection().testConnection();
    if (!mounted) return;
    setState(() => _isTesting = false);
    if (error == null) {
      showDialogMessage(context, "Test Connection".tl, "Connection successful".tl);
    } else {
      showDialogMessage(context, "Test Connection".tl, error);
    }
  }

  void _save() {
    final connection = _buildConnection();
    if (connection.name.isEmpty) {
      showDialogMessage(context, "Error".tl, "Name is required".tl);
      return;
    }
    if (connection.config.host.isEmpty) {
      showDialogMessage(context, "Error".tl, "Host is required".tl);
      return;
    }
    if (connection.config.share.isEmpty) {
      showDialogMessage(context, "Error".tl, "Share is required".tl);
      return;
    }

    // Read existing servers, replace or append
    final raw = appdata.settings['smbServers'];
    List<SmbConnection> servers;
    if (raw is List) {
      servers = raw
          .map(
            (e) => SmbConnection.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } else {
      servers = [];
    }

    if (_isEditing) {
      // Replace by name
      final oldName = widget.connection!.name;
      final idx = servers.indexWhere((s) => s.name == oldName);
      if (idx >= 0) {
        servers[idx] = connection;
      } else {
        servers.add(connection);
      }
    } else {
      servers.add(connection);
    }

    appdata.settings['smbServers'] =
        servers.map((e) => e.toJson()).toList();
    appdata.saveData();
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: _isEditing ? "Edit Server".tl : "Add Server".tl,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Name".tl,
                hintText: "My NAS",
                border: const OutlineInputBorder(),
              ),
              controller: _nameController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Host".tl,
                hintText: "192.168.1.100",
                border: const OutlineInputBorder(),
              ),
              controller: _hostController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Port".tl,
                hintText: "445",
                border: const OutlineInputBorder(),
              ),
              controller: _portController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Share".tl,
                hintText: "Comics",
                border: const OutlineInputBorder(),
              ),
              controller: _shareController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Username".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _usernameController,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Password".tl,
                border: const OutlineInputBorder(),
              ),
              controller: _passwordController,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: "Domain".tl,
                hintText: "WORKGROUP",
                border: const OutlineInputBorder(),
              ),
              controller: _domainController,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Button.outlined(
                    isLoading: _isTesting,
                    onPressed: _test,
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
                    isLoading: _isTesting,
                    onPressed: _save,
                    child: Text("Save".tl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ).paddingHorizontal(16),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Storage Path Dialog — supports local browsing and SMB URL entry
// ---------------------------------------------------------------------------
