import 'package:flutter/material.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:venera_nas/foundation/log.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';
import 'package:venera_nas/utils/comic_import.dart';
import 'package:venera_nas/utils/import_comic.dart';
import 'package:venera_nas/utils/io.dart';
import 'package:venera_nas/utils/translations.dart';
import 'package:venera_nas/foundation/app_theme.dart';

/// A dialog that allows the user to import comics from a .venera-comics file.
///
/// Handles file selection, displays import progress, and shows the final result
/// including counts of imported, skipped comics and any errors.
class ImportComicsDialog extends StatefulWidget {
  const ImportComicsDialog({super.key});

  @override
  State<ImportComicsDialog> createState() => _ImportComicsDialogState();
}

class _ImportComicsDialogState extends State<ImportComicsDialog> {
  bool _isImporting = false;
  bool _cancelled = false;
  int _current = 0;
  int _total = 0;
  String? _error;
  ImportResult? _result;

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return _buildResult();
    }
    return ContentDialog(
      title: "Import Migrated Comics".tl,
      content: _isImporting ? _buildProgress() : _buildInitial(),
      actions: _isImporting ? _buildProgressActions() : _buildActions(),
    );
  }

  Widget _buildInitial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Select a .venera-comics file to import.".tl,
        ).paddingHorizontal(16),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.sm,
              left: AppSpace.lg,
              right: AppSpace.lg,
            ),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: _total > 0 ? _current / _total : null),
        const SizedBox(height: 16),
        Text("$_current / $_total"),
      ],
    ).paddingHorizontal(16);
  }

  Widget _buildResult() {
    return ContentDialog(
      title: "Import Result".tl,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${"Imported".tl}: ${_result!.imported}").paddingHorizontal(16),
          Text("${"Skipped".tl}: ${_result!.skipped}").paddingHorizontal(16),
          if (_result!.errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              "Errors:".tl,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ).paddingHorizontal(16),
            ..._result!.errors.map((e) => Text("  $e").paddingHorizontal(16)),
          ],
        ],
      ),
      actions: [
        Button.normal(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text("OK".tl),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      Button.normal(
        onPressed: () => Navigator.of(context).pop(),
        child: Text("Cancel".tl),
      ),
      Button.normal(onPressed: _startImport, child: Text("Select File".tl)),
    ];
  }

  List<Widget> _buildProgressActions() {
    return [
      Button.normal(
        onPressed: () {
          setState(() {
            _cancelled = true;
          });
        },
        child: Text("Cancel".tl),
      ),
    ];
  }

  Future<void> _startImport() async {
    final file = await selectFile(ext: ['venera-comics']);
    if (file == null) return;
    // ⭐ 补 mounted 守卫 ✓（`await` 后本 State 可能已 dispose ✗；后续进度回调原本已有守卫 ✓）。
    if (!mounted) return;

    setState(() {
      _isImporting = true;
      _cancelled = false;
      _error = null;
    });

    try {
      final result = await ComicImporter.importComics(
        filePath: file.path,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _current = current;
            _total = total;
          });
        },
        isCancelled: () => _cancelled,
      );

      if (!mounted) return;

      if (_cancelled) {
        setState(() {
          _isImporting = false;
          _cancelled = false;
          _result = result;
        });
        return;
      }

      setState(() {
        _isImporting = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = "${"Import failed".tl}: $e";
      });
    }
  }
}

/// Dialog for importing comics from an SMB / NAS share.
class SmbImportDialog extends StatefulWidget {
  const SmbImportDialog({super.key});

  @override
  State<SmbImportDialog> createState() => _SmbImportDialogState();
}

class _SmbImportDialogState extends State<SmbImportDialog> {
  List<SmbConnection> _servers = [];
  SmbConnection? _selectedServer;
  String _rootPath = '';
  bool _isScanning = false;
  int _current = 0;
  int _total = 0;
  String? _scanResult;

  /// ⭐ 2026-10-24：**取消标记** ✓ —— 取消时置 true ✓，扫描循环逐个目录检查 ✓；
  /// 取消后**不写入任何记录** ✓（原来 Cancel 是空函数 ✗，点了没反应 ✓）。
  bool _cancelRequested = false;

  static List<SmbConnection> _loadServers() {
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

  @override
  void initState() {
    super.initState();
    _servers = _loadServers();
    if (_servers.isNotEmpty) {
      _selectedServer = _servers.first;
    }
  }

  Future<void> _startScan() async {
    if (_selectedServer == null) {
      context.showMessage(message: "请选择一个服务器".tl);
      return;
    }
    if (_rootPath.trim().isEmpty) {
      context.showMessage(message: "请输入根路径".tl);
      return;
    }

    setState(() {
      _isScanning = true;
      _current = 0;
      _total = 0;
      _scanResult = null;
      _cancelRequested = false;
    });

    try {
      final rootPath = _rootPath.trim();
      final comics = await ImportComic.smb(
        config: _selectedServer!.config,
        rootPath: rootPath,
        favoriteFolder: _selectedServer!.name,
        // ⭐ 2026-10-24：**进度** ✓（有大目录时按"已检查目录数/总目录数"显示 ✓）。
        onProgress: (current, total) {
          if (!mounted || _cancelRequested) return;
          setState(() {
            _current = current;
            _total = total;
          });
        },
        // ⭐ 2026-10-24：**取消** ✓ —— 取消后由下方统一收尾 ✓（不写任何记录 ✓）。
        isCancelled: () => _cancelRequested,
      );

      if (!mounted) return;
      if (_cancelRequested) {
        setState(() {
          _isScanning = false;
          _cancelRequested = false;
        });
        context.showMessage(message: "已取消扫描".tl);
        return;
      }
      LocalManager().notifyChanges();
      setState(() {
        _isScanning = false;
        _scanResult = "从 @b 导入了 @a 部漫画".tlParams({
          'a': comics.length,
          'b': _selectedServer!.name,
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _cancelRequested = false;
        _scanResult = "${"导入失败".tl}: $e";
      });
      Log.error("SMB Import", e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_servers.isEmpty) {
      return ContentDialog(
        title: "SMB / NAS 导入".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "未配置 SMB 服务器。请先在 设置 > SMB / NAS 服务器 中添加服务器。".tl,
            ).paddingHorizontal(16),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          Button.normal(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("OK".tl),
          ),
        ],
      );
    }

    if (_scanResult != null) {
      return ContentDialog(
        title: "扫描完成".tl,
        content: Text(_scanResult!).paddingHorizontal(16),
        actions: [
          Button.normal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text("OK".tl),
          ),
        ],
      );
    }

    return ContentDialog(
      title: "SMB / NAS 导入".tl,
      content: _isScanning ? _buildProgress() : _buildForm(_servers),
      actions: _isScanning ? _buildProgressActions() : _buildFormActions(),
    );
  }

  Widget _buildForm(List<SmbConnection> servers) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⭐ 2026-10-25（用户反馈 ✓）：服务器选择改用**统一 Select 构件** ✓ ——
        // 原来用 `DropdownButtonFormField` ✗ ⇒ 弹出的菜单样式与 App 其它菜单不一致 ✗
        //（灰底矩形、无外观体系 ✓）。`Select` 走 `showMenu` + 外观体系 ✓，点击展开样式统一 ✓。
        Text(
          "服务器".tl,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ).paddingHorizontal(16),
        const SizedBox(height: AppSpace.xs),
        Select(
          current: _selectedServer?.name,
          values: servers.map((s) => s.name).toList(),
          onTap: (index) {
            if (index >= 0 && index < servers.length) {
              setState(() => _selectedServer = servers[index]);
            }
          },
        ).paddingHorizontal(16),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: "根路径".tl,
            hintText: 'Comics/Manga',
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _rootPath = v,
        ).paddingHorizontal(16),
        const SizedBox(height: 8),
        Text(
          "SMB 共享中漫画目录所在的路径。".tl,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ).paddingHorizontal(16),
      ],
    );
  }

  Widget _buildProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: _total > 0 ? _current / _total : null),
        const SizedBox(height: 16),
        Text(_cancelRequested ? "正在取消…".tl : "正在扫描...".tl),
        if (_total > 0) Text("$_current / $_total"),
      ],
    ).paddingHorizontal(16);
  }

  List<Widget> _buildFormActions() {
    return [
      Button.normal(
        onPressed: () => Navigator.of(context).pop(),
        child: Text("Cancel".tl),
      ),
      // ⭐ 2026-10-25（用户反馈 ✓）：两个按钮**挨在一起** ✗ ⇒ 补标准间距 ✓
      //（外观规范 §4.2.2：相邻按钮必须留 `AppSpace.sm` ✓）。
      const SizedBox(width: AppSpace.sm),
      Button.normal(onPressed: _startScan, child: Text("开始扫描".tl)),
    ];
  }

  List<Widget> _buildProgressActions() {
    return [
      // ⭐ 2026-10-24：**Cancel 现在真的有效** ✓（原来 `onPressed: () {}` 是空函数 ✗）。
      // 点击后置标记 ✓ ⇒ 扫描循环在下一个目录前停下 ✓ ⇒ 不写入任何记录 ✓。
      Button.normal(
        onPressed: () {
          if (_cancelRequested) return;
          setState(() => _cancelRequested = true);
        },
        child: Text("Cancel".tl),
      ),
      const SizedBox(width: AppSpace.sm),
      Button.normal(
        onPressed: () {
          // ⭐ 2026-10-25（用户反馈 ✓）：扫描中也要能**关闭弹窗** ✓
          //（否则卡住时弹窗关不掉 ✗）；关闭后扫描仍会按取消标记收尾 ✓。
          if (!_cancelRequested) {
            setState(() => _cancelRequested = true);
          }
          Navigator.of(context).pop();
        },
        child: Text("关闭".tl),
      ),
    ];
  }
}
