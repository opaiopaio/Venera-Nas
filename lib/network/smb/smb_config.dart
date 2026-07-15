/// Configuration for connecting to an SMB share.
class SmbConfig {
  final String host;
  final int port;
  final String share;
  final String username;
  final String password;
  final String domain;

  const SmbConfig({
    required this.host,
    this.port = 445,
    required this.share,
    this.username = '',
    this.password = '',
    this.domain = '',
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
  };

  factory SmbConfig.fromJson(Map<String, dynamic> json) => SmbConfig(
    host: json['host'] as String,
    port: (json['port'] as num?)?.toInt() ?? 445,
    share: json['share'] as String,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    domain: json['domain'] as String? ?? '',
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

/// Represents an entry (file or directory) on an SMB share.
class SmbEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
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
