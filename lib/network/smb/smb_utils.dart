import 'package:venera_nas/network/smb/smb_config.dart';

/// Returns `true` if [path] is an SMB (smb://) URL.
bool isSmbPath(String path) => path.startsWith('smb://');

/// Parse [SmbConfig] from an `smb://` URL.
///
/// Credentials embedded in the URL's userinfo are decoded.
/// For `smb://user:pass@host:port/share/path/to/file`,
/// extracts host, port, share, username, and password.
SmbConfig parseSmbConfigFromUrl(String url) {
  final uri = Uri.parse(url);
  final parts = uri.pathSegments;
  final share = parts.isNotEmpty ? parts.first : '';
  final userInfo = uri.userInfo.split(':');
  return SmbConfig(
    host: uri.host,
    port: uri.hasPort ? uri.port : 445,
    share: share,
    username: userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : '',
    password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : '',
  );
}

/// Extract the share-relative path from an `smb://` URL.
///
/// For `smb://host/share/dir/subdir/file.jpg`, returns `dir/subdir/file.jpg`.
/// For `smb://host/share` (no path beyond share), returns an empty string.
String smbPathFromUrl(String url) {
  final uri = Uri.parse(url);
  final segments = uri.pathSegments;
  if (segments.length <= 1) return '';
  return segments.sublist(1).join('/');
}

/// Build a share-relative path for a file from an `smb://` URL.
///
/// Alias for [smbPathFromUrl].
String smbFilePathFromUrl(String url) => smbPathFromUrl(url);

/// Normalize an SMB path for display or joining.
///
/// Strips trailing slashes and ensures consistent formatting.
String normalizeSmbPath(String path) {
  var normalized = path;
  while (normalized.endsWith('/') || normalized.endsWith('\\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}


