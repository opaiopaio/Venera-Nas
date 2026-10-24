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
  Future<String?> testConnection() => _testWith(config);

  /// ⭐ 2026-10-25：**测试连接 + 自动诊断** ✓
  ///
  /// 用户实测常见问题（Windows 事件/错误码 ✓）：
  /// - 手动选了 `SMB 3.1.1` + 加密 ✓，但路由器上的 Samba 只支持到 SMB 3.0/3.0.2、
  ///   或**不支持加密** ✗ ⇒ 协商返回 `SMB2_STATUS_NOT_SUPPORTED (0xc00000bb)` ✗
  /// - 这时用户只看到一串英文错误码 ✓，不知道该怎么改 ✗
  ///
  /// 本方法：先按**当前配置**试 ✓；失败就**逐项降级**再试 ✓（不改用户已保存的配置 ✗），
  /// 并把"哪一套参数能连"直接告诉用户 ✓ ⇒ 用户按提示改即可 ✓。
  Future<String?> testConnectionWithDiagnosis() async {
    final originalError = await _testWith(config);
    if (originalError == null) return null;

    final hint = _hintFor(originalError);

    // ⚠️ 只在"像是协议/协商问题"时才逐项降级 ✓ ——
    // 否则连不上的主机（网络不通 ✓）会把同样的失败重试 4 次，用户要等几十秒 ✗。
    final looksLikeProtocolIssue =
        originalError.contains('0xc00000bb') ||
        originalError.contains('STATUS_NOT_SUPPORTED') ||
        originalError.toLowerCase().contains('negotiate');
    if (!looksLikeProtocolIssue) {
      return '$originalError$hint';
    }
    final fallbacks = <String, SmbConfig>{
      '协商版本 = 自动': config.copyWith(version: Smb2Version.any, seal: false),
      '协商版本 = 自动，且关闭加密': config.copyWith(
        version: Smb2Version.any,
        seal: false,
        signing: false,
      ),
      '协商版本 = SMB 3.0.2（兼容老 Samba），且关闭加密': config.copyWith(
        version: Smb2Version.v302,
        seal: false,
      ),
      '协商版本 = SMB 2.1（兼容老 Samba），且关闭加密': config.copyWith(
        version: Smb2Version.v210,
        seal: false,
      ),
    };

    for (final entry in fallbacks.entries) {
      final err = await _testWith(entry.value);
      if (err == null) {
        return '$originalError$hint\n\n'
            '✅ 诊断：用「${entry.key}」可以连接 ✓\n'
            '建议把协商版本改成对应值、并关闭 SMB3 加密后再保存 ✓';
      }
    }

    return '$originalError$hint\n\n'
        '❌ 自动降级（自动版本 / 3.0.2 / 2.1，均关闭加密）也连不上 ✗\n'
        '请检查：① 路由器/ NAS 是否**只开了 SMB1**（本应用不支持 SMB1 ✗）\n'
        '② 共享名与账号密码 ✓ ③ 端口必须是 445 ✓';
  }

  /// 常见 SMB 错误码 → 中文提示 ✓（只做提示 ✓，不改变连接行为 ✓）。
  static String _hintFor(String message) {
    bool has(String s) => message.contains(s);
    if (has('0xc00000bb') || has('STATUS_NOT_SUPPORTED')) {
      return '\n（该错误码通常表示：**服务器不支持**所选的 SMB 版本或加密 ✓）';
    }
    if (has('0xc000006d') || has('LOGON_FAILURE')) {
      return '\n（该错误码通常表示：**账号或密码不对** ✓）';
    }
    if (has('0xc0000022') || has('ACCESS_DENIED')) {
      return '\n（该错误码通常表示：**无权访问该共享** ✓）';
    }
    if (has('0xc00000cc') || has('BAD_NETWORK_NAME')) {
      return '\n（该错误码通常表示：**共享名不存在** ✓）';
    }
    return '';
  }

  Future<String?> _testWith(SmbConfig target) async {
    // ⚠️ 2026-10-24：底层库无端口参数 ⇒ 非 445 端口无法测试，直接给出明确原因 ✓（不再静默失败 ✗）。
    if (target.port != 445) {
      return '端口 ${target.port} 暂不支持：底层库仅支持 445 端口。';
    }
    try {
      final pool = await Smb2Pool.connect(
        host: target.host,
        share: target.share,
        user: target.username,
        password: target.password,
        domain: target.domain,
        timeoutSeconds: 10,
        workers: 1,
        // ⭐ 2026-10-24：协议选项透传 ✓（与正式连接保持一致 ✓，避免"测试通过但实际连不上" ✗）。
        signing: target.signing,
        seal: target.seal,
        version: target.version,
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
