import 'package:dart_smb2/dart_smb2.dart';

/// Configuration for connecting to an SMB share.
///
/// Stores the host, port, share name, and optional credentials
/// required to establish an SMB session.
class SmbConfig {
  /// SMB server hostname or IP address.
  final String host;

  /// SMB port (default: 445).
  final int port;

  /// Name of the shared folder on the server.
  final String share;

  /// Username for authentication (empty string if anonymous).
  final String username;

  /// Password for authentication (empty string if anonymous).
  final String password;

  /// Windows domain for authentication (default: empty string).
  final String domain;

  /// ⭐ 2026-10-24：**要求消息签名** ✓（服务器"强制签名"时必须开 ✓，否则协商失败 ✗）。
  final bool signing;

  /// ⭐ 2026-10-24：**SMB3 加密（seal）** ✓（服务器要求加密时必须开 ✓；要求至少 SMB3 ✓）。
  final bool seal;

  /// ⭐ 2026-10-24：**协商方言** ✓（默认 `any` = 让服务器挑最高 ✓；
  /// 老设备可强制 `v210`/`v300` 等 ✓；`seal` 必须 ≥ `any3` ✓）。
  final Smb2Version version;

  const SmbConfig({
    required this.host,
    this.port = 445,
    required this.share,
    this.username = '',
    this.password = '',
    this.domain = '',
    this.signing = false,
    this.seal = false,
    this.version = Smb2Version.any,
  });

  /// Builds an SMB URL from this config: smb://host:port/share/path
  String buildUrl([String path = '']) {
    final buffer = StringBuffer('smb://');
    buffer.write(host);
    if (port != 445) {
      buffer.write(':$port');
    }
    buffer.write('/$share');
    if (path.isNotEmpty) {
      final normalized = path.replaceAll('\\', '/');
      buffer.write('/${normalized.replaceAll(RegExp(r'^/+'), '')}');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'share': share,
    'username': username,
    'password': password,
    'domain': domain,
    // ⭐ 2026-10-24：新增协议选项 ✓（老数据没有这些键 ⇒ 取默认值 ✓ 向后兼容 ✓）。
    'signing': signing,
    'seal': seal,
    'version': version.name,
  };

  factory SmbConfig.fromJson(Map<String, dynamic> json) => SmbConfig(
    host: json['host'] as String,
    port: (json['port'] as num?)?.toInt() ?? 445,
    share: json['share'] as String,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
    signing: json['signing'] as bool? ?? false,
    seal: json['seal'] as bool? ?? false,
    version: _versionFromName(json['version'] as String?),
  );

  static Smb2Version _versionFromName(String? name) {
    if (name == null || name.isEmpty) return Smb2Version.any;
    for (final v in Smb2Version.values) {
      if (v.name == name) return v;
    }
    return Smb2Version.any;
  }

  /// ⭐ 2026-10-25：**复制并覆盖部分字段** ✓ —— 供"测试连接自动诊断"逐项降级试用 ✓
  ///（如：自动版本 / 关闭加密 / 关闭签名 ✓）。
  SmbConfig copyWith({
    String? host,
    int? port,
    String? share,
    String? username,
    String? password,
    String? domain,
    bool? signing,
    bool? seal,
    Smb2Version? version,
  }) => SmbConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    share: share ?? this.share,
    username: username ?? this.username,
    password: password ?? this.password,
    domain: domain ?? this.domain,
    signing: signing ?? this.signing,
    seal: seal ?? this.seal,
    version: version ?? this.version,
  );

  @override
  bool operator ==(Object other) =>
      other is SmbConfig &&
      other.host == host &&
      other.port == port &&
      other.share == share &&
      other.username == username;

  @override
  int get hashCode => Object.hash(host, port, share, username);
}

/// Represents a file or directory entry on an SMB share.
///
/// Returned by [SmbClient.listDirectory] and similar operations.
class SmbEntry {
  /// The entry name (file or directory name only).
  final String name;

  /// The full share-relative path.
  final String path;

  /// Whether this entry is a directory.
  final bool isDirectory;

  /// File size in bytes (0 for directories).
  final int size;

  /// Last modification timestamp.
  final DateTime modified;

  SmbEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    DateTime? modified,
  }) : modified = modified ?? DateTime(1970);

  bool get isFile => !isDirectory;

  /// File extension without the leading dot, lowercased.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  @override
  String toString() => 'SmbEntry($name, dir=$isDirectory, size=$size)';
}
