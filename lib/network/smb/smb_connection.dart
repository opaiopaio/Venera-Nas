import 'dart:convert';

import 'package:dart_smb2/dart_smb2.dart';

import 'smb_config.dart';

/// A saved SMB connection profile that can be serialized to/from JSON.
///
/// The password is stored in the JSON. Callers should encrypt it before
/// persisting if the storage target is not already protected.
class SmbConnection {
  final String name;
  final SmbConfig config;

  const SmbConnection({required this.name, required this.config});

  Map<String, dynamic> toJson() => {'name': name, 'config': config.toJson()};

  factory SmbConnection.fromJson(Map<String, dynamic> json) => SmbConnection(
    name: json['name'] as String,
    config: SmbConfig.fromJson(json['config'] as Map<String, dynamic>),
  );

  /// Serialize a list of connections to a JSON string.
  static String encodeList(List<SmbConnection> connections) =>
      jsonEncode(connections.map((c) => c.toJson()).toList());

  /// Deserialize a list of connections from a JSON string.
  static List<SmbConnection> decodeList(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list
        .map((e) => SmbConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Try to connect to the SMB share and list the root directory.
  ///
  /// Returns null on success, or an error message string on failure.
  Future<String?> testConnection() async {
    // ⚠️ 2026-10-24：底层库无端口参数 ⇒ 非 445 端口无法测试，直接给出明确原因 ✓（不再静默失败 ✗）。
    if (config.port != 445) {
      return '端口 ${config.port} 暂不支持：底层库仅支持 445 端口。';
    }
    try {
      final pool = await Smb2Pool.connect(
        host: config.host,
        share: config.share,
        user: config.username,
        password: config.password,
        domain: config.domain,
        timeoutSeconds: 10,
        workers: 1,
        // ⭐ 2026-10-24：协议选项透传 ✓（与正式连接保持一致 ✓，避免"测试通过但实际连不上" ✗）。
        signing: config.signing,
        seal: config.seal,
        version: config.version,
      );
      try {
        await pool.listDirectory('');
        return null;
      } finally {
        await pool.disconnect();
      }
    } on Smb2Exception catch (e) {
      final type = e.type;
      if (type == Smb2ErrorType.auth) {
        return 'Authentication failed: ${e.message}';
      } else if (type == Smb2ErrorType.connection ||
          type == Smb2ErrorType.timeout) {
        return 'Connection failed: ${e.message}';
      } else if (type == Smb2ErrorType.fileNotFound) {
        // The share itself may be empty or root is not listable.
        // The connection worked — return null.
        return null;
      } else {
        return 'SMB error: ${e.message}';
      }
    } catch (e) {
      return e.toString();
    }
  }
}
