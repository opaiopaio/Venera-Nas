import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';

/// Returns `true` if [path] is an SMB (smb://) URL.
bool isSmbPath(String path) => path.startsWith('smb://');

/// ⭐ 2026-10-24：按 `host + share` 找**已保存的服务器配置** ✓。
///
/// 为什么需要 ✓：导入 SMB 漫画时落库的目录是 `smb://host/share/path` ✓，
/// 而 `buildUrl()` **不写账号密码**（安全考虑 ✓）⇒ 之后读图/列目录只能拿到"无凭据"的 URL ✓
/// ⇒ 需要认证的共享会**静默走匿名连接** ✗（此前后者能用只是因为共享开了 guest ✓）。
/// 现在：URL 里没有凭据时回退到设置里保存的同 host+share 配置 ✓ ——
/// ⭐ **凭据永远不进 URL / 不进备份** ✓（只在本机内存里取用 ✓）。
SmbConnection? _findSavedConnection(String host, String share) {
  final raw = appdata.settings['smbServers'];
  if (raw is! List) return null;
  for (final item in raw) {
    if (item is! Map) continue;
    try {
      final conn = SmbConnection.fromJson(Map<String, dynamic>.from(item));
      if (conn.config.host.toLowerCase() == host.toLowerCase() &&
          conn.config.share == share) {
        return conn;
      }
    } catch (_) {
      // 单条配置损坏不影响其它配置 ✓。
    }
  }
  return null;
}

/// Parse [SmbConfig] from an `smb://` URL.
///
/// Credentials embedded in the URL's userinfo are decoded.
/// For `smb://user:pass@host:port/share/path/to/file`,
/// extracts host, port, share, username, and password.
///
/// ⭐ 2026-10-24：URL 不带凭据时**回退到已保存的服务器配置** ✓，
/// 并把 domain / 签名 / 加密 / 方言一起带上 ✓（这些无法编码进 URL ✓）。
SmbConfig parseSmbConfigFromUrl(String url) {
  final uri = Uri.parse(url);
  final parts = uri.pathSegments;
  final share = parts.isNotEmpty ? parts.first : '';
  final userInfo = uri.userInfo.split(':');
  var username = uri.userInfo.isNotEmpty
      ? Uri.decodeComponent(userInfo[0])
      : '';
  var password = userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : '';
  var domain = '';
  var signing = false;
  var seal = false;
  var version = Smb2Version.any;
  final saved = _findSavedConnection(uri.host, share);
  if (saved != null) {
    if (username.isEmpty) username = saved.config.username;
    if (password.isEmpty) password = saved.config.password;
    // domain / 协议选项**只能**来自保存的配置 ✓（URL 里没有位置放它们 ✓）。
    domain = saved.config.domain;
    signing = saved.config.signing;
    seal = saved.config.seal;
    version = saved.config.version;
  }
  return SmbConfig(
    host: uri.host,
    port: uri.hasPort ? uri.port : 445,
    share: share,
    username: username,
    password: password,
    domain: domain,
    signing: signing,
    seal: seal,
    version: version,
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
