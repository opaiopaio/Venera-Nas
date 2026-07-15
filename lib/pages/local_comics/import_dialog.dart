import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/smb/smb_client.dart';
import 'package:venera/network/smb/smb_config.dart';
import 'package:venera/network/smb/smb_connection.dart';
import 'package:venera/utils/comic_import.dart';
import 'package:venera/utils/import_comic.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

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
            padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text("OK".tl),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text("Cancel".tl),
      ),
      FilledButton(onPressed: _startImport, child: Text("Select File".tl)),
    ];
  }

  List<Widget> _buildProgressActions() {
    return [
      TextButton(
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
  bool _cancelled = false;
  int _current = 0;
  int _total = 0;
  String? _scanResult;

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
      context.showMessage(message: "Please select a server".tl);
      return;
    }
    if (_rootPath.trim().isEmpty) {
      context.showMessage(message: "Please enter a root path".tl);
      return;
    }

    setState(() {
      _isScanning = true;
      _cancelled = false;
      _current = 0;
      _total = 0;
      _scanResult = null;
    });

    try {
      final rootPath = _rootPath.trim();
      final comics = await ImportComic.smb(
        config: _selectedServer!.config,
        rootPath: rootPath,
        favoriteFolder: _selectedServer!.name,
      );

      if (!mounted) return;
      LocalManager().notifyListeners();
      setState(() {
        _isScanning = false;
        _scanResult = "Imported @a comics from @b"
            .tlParams({'a': comics.length, 'b': _selectedServer!.name});
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _scanResult = "${"Import failed".tl}: $e";
      });
      Log.error("SMB Import", e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_servers.isEmpty) {
      return ContentDialog(
        title: "SMB / NAS Import".tl,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "No SMB servers configured. Please add a server in Settings > SMB / NAS Servers first."
                  .tl,
            ).paddingHorizontal(16),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("OK".tl),
          ),
        ],
      );
    }

    if (_scanResult != null) {
      return ContentDialog(
        title: "Scan Complete".tl,
        content: Text(_scanResult!).paddingHorizontal(16),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text("OK".tl),
          ),
        ],
      );
    }

    return ContentDialog(
      title: "SMB / NAS Import".tl,
      content: _isScanning ? _buildProgress() : _buildForm(_servers),
      actions: _isScanning ? _buildProgressActions() : _buildFormActions(),
    );
  }

  Widget _buildForm(List<SmbConnection> servers) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<SmbConnection>(
          value: _selectedServer,
          decoration: InputDecoration(
            labelText: "Server".tl,
            border: const OutlineInputBorder(),
          ),
          items: servers.map((s) {
            return DropdownMenuItem(value: s, child: Text(s.name));
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selectedServer = v);
            }
          },
        ).paddingHorizontal(16),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: "Root Path".tl,
            hintText: 'Comics/Manga',
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => _rootPath = v,
        ).paddingHorizontal(16),
        const SizedBox(height: 8),
        Text(
          "Path on the SMB share where comic directories are located.".tl,
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
        LinearProgressIndicator(
          value: _total > 0 ? _current / _total : null,
        ),
        const SizedBox(height: 16),
        Text("Scanning...".tl),
        if (_total > 0) Text("$_current / $_total"),
      ],
    ).paddingHorizontal(16);
  }

  List<Widget> _buildFormActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text("Cancel".tl),
      ),
      FilledButton(onPressed: _startScan, child: Text("Scan".tl)),
    ];
  }

  List<Widget> _buildProgressActions() {
    return [
      TextButton(
        onPressed: () {
          setState(() => _cancelled = true);
        },
        child: Text("Cancel".tl),
      ),
    ];
  }
}
