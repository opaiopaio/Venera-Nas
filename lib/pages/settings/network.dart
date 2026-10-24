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

  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;

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
    super.initState();
    var proxy = appdata.settings['proxy'];
    parseProxyString(proxy);
    _hostCtrl = TextEditingController(text: host);
    _portCtrl = TextEditingController(text: port);
    _usernameCtrl = TextEditingController(text: username);
    _passwordCtrl = TextEditingController(text: password);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      popupStyle: true,
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
            controller: _hostCtrl,
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
            controller: _portCtrl,
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
            controller: _usernameCtrl,
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
            controller: _passwordCtrl,
            onChanged: (v) {
              password = v;
            },
          ),
          const SizedBox(height: 16),
          Button.normal(
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
    final raw = appdata.settings['dnsOverrides'];
    if (raw is Map) {
      for (var entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          overrides.add((
            TextEditingController(text: entry.key),
            TextEditingController(text: entry.value),
          ));
        }
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
      popupStyle: true,
      title: "DNS Overrides".tl,
      tailing: [
        // H2 `.icon` 专轮：DNS 覆盖的「Save」→ 自绘 `Button` + `pillLabel` ✓
        Button.normal(
          onPressed: () async {
            await _save();
            if (context.mounted) {
              context.pop();
            }
          },
          child: pillLabel(Icons.save, "Save".tl),
        ),
      ],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _SwitchSetting(
              title: "Enable DNS Overrides".tl,
              settingKey: "enableDnsOverrides",
              masked: true,
            ),
            _SwitchSetting(
              title: "Server Name Indication",
              settingKey: "sni",
              masked: true,
            ),
            const SizedBox(height: 8),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: AppSpace.sm),
              color: context.colorScheme.outlineVariant,
            ),
            for (var i = 0; i < overrides.length; i++) buildOverride(i),
            const SizedBox(height: 8),
            // H2 `.icon` 专轮：DNS 覆盖的「Add」→ 自绘 `Button` + `pillLabel` ✓
            Button.normal(
              onPressed: () {
                setState(() {
                  overrides.add((
                    TextEditingController(),
                    TextEditingController(),
                  ));
                });
              },
              child: pillLabel(Icons.add, "Add".tl),
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
      margin: EdgeInsets.symmetric(horizontal: AppSpace.sm),
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
  /// ⭐ 2026-10-25：重置按钮的**进行中态** ✓ —— 重置会先等在途读/断开连接
  /// （最多数秒 ✓），期间重复点击会叠加关闭流程 ✗，按钮必须禁用并给出反馈 ✓。
  bool _isResettingSmb = false;

  List<SmbConnection> get servers {
    final raw = appdata.settings['smbServers'];
    if (raw is! List) return [];
    try {
      return raw
          .map(
            (e) => SmbConnection.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  set servers(List<SmbConnection> value) {
    appdata.settings['smbServers'] = value.map((e) => e.toJson()).toList();
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

  /// ⭐ 2026-10-25：**重置 SMB 连接** ✓（卡住时的恢复手段 ✓）。
  Future<void> _resetSmbConnection() async {
    if (_isResettingSmb) return;
    setState(() => _isResettingSmb = true);
    try {
      await ReaderImageProvider.resetSmbRuntime();
      if (!mounted) return;
      context.showMessage(message: "已重置 SMB 连接，请重新尝试".tl);
    } finally {
      // 无论成功/失败都恢复按钮 ✓（避免异常后永远转圈 ✗）。
      if (mounted) {
        setState(() => _isResettingSmb = false);
      }
    }
  }

  Future<void> _testServer(int index) async {
    final connection = servers[index];
    setState(() {}); // trigger rebuild for loading indicator if needed
    // ⭐ 2026-10-25（用户实测追问 ✓）：**列表页的"快速测试"也要走降级链** ✓ ——
    // 原来这里只按**当前保存的配置**试一次 ✗ ⇒ 用户开着签名/加密时会看到原始报错 ✗，
    // 但实际读图/下载会自动降级（关签名 → 自动 → 3.0.2 → 2.1 ✓）⇒ 两处结论不一致 ✗。
    final error = await connection.testConnectionWithDiagnosis();
    if (!mounted) return;
    if (error == null) {
      showDialogMessage(
        context,
        "Test Connection".tl,
        "Connection successful".tl,
      );
    } else if (error.startsWith('✅')) {
      // 降级后可用 ✓：不按"失败"展示 ✗（方法内部已给出"已自动降级为…"的说明 ✓）。
      showDialogMessage(context, "Test Connection".tl, error);
    } else {
      showDialogMessage(context, "Test Connection".tl, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = servers;

    return PopUpWidgetScaffold(
      popupStyle: true,
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
                        // ⭐ UI（2026-10-24）：全局 `iconButtonTheme` 会给每个 `IconButton` 注入填充底色 ✓
                        // ⇒ 相邻无间距时会**贴成一片** ✗（用户实测：三个按钮的遮罩连在一起 ✓）。
                        // 惯例同 `components/select_toolbar.dart:55-61` 与 `comic_source_page.dart:1000` ✓。
                        const SizedBox(width: AppSpace.sm),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          tooltip: "Edit".tl,
                          onPressed: () => _editServer(index),
                        ),
                        const SizedBox(width: AppSpace.sm),
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
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Button.filled(
                    onPressed: _addServer,
                    child: Text("Add Server".tl),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                // ⭐ 2026-10-25：**SMB 卡住时的恢复入口** ✓ ——
                // 若某个 SMB 操作卡死（服务器无响应 ✓），列表/扫描/读图会一直等待 ✗；
                // 点这里可**断开复用连接 + 释放全局闸门** ✓，无需重启 App ✓。
                SizedBox(
                  width: double.infinity,
                  child: Button.outlined(
                    isLoading: _isResettingSmb,
                    onPressed: _isResettingSmb ? null : _resetSmbConnection,
                    child: Text("重置 SMB 连接（卡住时用）".tl),
                  ),
                ),
              ],
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

  // ⭐ 2026-10-24：SMB 协议选项 UI state ✓（服务器"强制签名/加密"或需指定方言时用 ✓）。
  late bool _signing;
  late bool _seal;
  late Smb2Version _version;

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
    _usernameController = TextEditingController(text: c?.config.username ?? '');
    _passwordController = TextEditingController(text: c?.config.password ?? '');
    _domainController = TextEditingController(text: c?.config.domain ?? '');
    _signing = c?.config.signing ?? false;
    _seal = c?.config.seal ?? false;
    _version = c?.config.version ?? Smb2Version.any;
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
        signing: _signing,
        seal: _seal,
        version: _version,
      ),
    );
  }

  /// 加密（seal）要求 SMB3 ✓ —— 选项不匹配时直接拦下 ✓，避免用户只看到"连不上" ✗。
  String? _validateProtocolOptions() {
    if (!_seal) return null;
    const smb3Versions = {
      Smb2Version.any3,
      Smb2Version.v300,
      Smb2Version.v302,
      Smb2Version.v311,
    };
    if (smb3Versions.contains(_version)) return null;
    return "加密（seal）需要 SMB3：请把协商版本改为「SMB3」或更高。";
  }

  Future<void> _test() async {
    if (_isTesting) return;
    final protocolError = _validateProtocolOptions();
    if (protocolError != null) {
      showDialogMessage(context, "Test Connection".tl, protocolError);
      return;
    }
    setState(() => _isTesting = true);
    // ⭐ 2026-10-25：用**带诊断**的测试 ✓ —— 失败时自动降级试出"哪套参数能连" ✓，
    // 直接告诉用户该把协商版本/加密改成什么 ✓（错误码 0xc00000bb 之类用户看不懂 ✗）。
    final error = await _buildConnection().testConnectionWithDiagnosis();
    if (!mounted) return;
    setState(() => _isTesting = false);
    if (error == null) {
      showDialogMessage(
        context,
        "Test Connection".tl,
        "Connection successful".tl,
      );
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
    final protocolError = _validateProtocolOptions();
    if (protocolError != null) {
      showDialogMessage(context, "Error".tl, protocolError);
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

    appdata.settings['smbServers'] = servers.map((e) => e.toJson()).toList();
    appdata.saveData();
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      popupStyle: true,
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
                // ⭐ 2026-10-24：底层库无端口参数 ⇒ 明确告知用户只有 445可用 ✓（不再静默连错 ✗）。
                helperText: '当前底层库仅支持 445 端口',
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
            // ⭐ 2026-10-24：**SMB 协议选项** ✓ —— 服务器"强制签名/加密"或需要指定方言时用 ✓
            //（libsmb2 支持 SMB2/3 ✓；这些选项直接透传给 `Smb2Pool.connect` ✓）。
            const SizedBox(height: AppSpace.lg),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _signing,
              onChanged: (v) => setState(() => _signing = v),
              title: const Text("要求消息签名（signing）"),
              // ⭐ 2026-10-25：不点名具体实现、不下绝对结论 ✓ —— 只说"开不了就关掉试试" ✓。
              subtitle: const Text("服务器要求签名时开启；若开启后无法连接，可尝试关闭"),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _seal,
              onChanged: (v) => setState(() => _seal = v),
              title: const Text("SMB3 加密（seal）"),
              subtitle: const Text("服务器要求加密时开启（需 SMB3）；若无法连接，可尝试关闭"),
            ),
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<Smb2Version>(
              initialValue: _version,
              decoration: const InputDecoration(
                labelText: "协商版本（dialect）",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: Smb2Version.any, child: Text("自动（推荐）")),
                DropdownMenuItem(
                  value: Smb2Version.any2,
                  child: Text("任意 SMB2"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.any3,
                  child: Text("任意 SMB3"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.v202,
                  child: Text("SMB 2.0.2"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.v210,
                  child: Text("SMB 2.1"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.v300,
                  child: Text("SMB 3.0"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.v302,
                  child: Text("SMB 3.0.2"),
                ),
                DropdownMenuItem(
                  value: Smb2Version.v311,
                  child: Text("SMB 3.1.1"),
                ),
              ],
              onChanged: (v) => setState(() => _version = v ?? Smb2Version.any),
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
