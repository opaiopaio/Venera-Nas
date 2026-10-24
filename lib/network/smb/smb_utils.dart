import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';

/// Returns `true` if [path] is an SMB (smb://) URL.
bool isSmbPath(String path) => path.startsWith('smb://');

/// ⭐ 2026-10-24：**剥离 SMB 路径里的账号密码** ✓
///
/// 背景（安全 ✓）：`smbDownloadPath` 是"下载到 NAS"的根路径 ✓，用户可能把
/// `smb://user:pass@nas/share/dir` 整段粘进来 ✓ ⇒ 凭据会**明文留在设置里** ✗
///（虽然同步/备份/导出已剔除该键 ✓，但仍不该存 ✓）。
/// 凭据应放在「SMB / NAS 服务器」配置里 ✓（读取时按 host+share 回退 ✓）。
///
/// 例：`smb://user:pass@nas/share/dir` ⇒ `smb://nas/share/dir` ✓
/// 非 SMB 路径、或本来就没有凭据的路径 ⇒ **原样返回** ✓。
String sanitizeSmbPathCredentials(String path) {
  if (!isSmbPath(path)) return path;
  final uri = Uri.parse(path);
  if (uri.userInfo.isEmpty) return path;
  final stripped = uri.replace(userInfo: '');
  if (stripped.userInfo.isEmpty) {
    return stripped.toString();
  }
  // 兜底：极端情况下 `replace` 未清掉 userinfo ⇒ 手工拼接 ✓。
  final buffer = StringBuffer('smb://');
  buffer.write(uri.host);
  if (uri.hasPort) {
    buffer.write(':${uri.port}');
  }
  for (final segment in uri.pathSegments) {
    buffer.write('/$segment');
  }
  return buffer.toString();
}

/// ⭐ 2026-10-24：按 `host + share` 找**已保存的服务器配置** ✓。
///
/// 为什么需要 ✓：导入 SMB 漫画时落库的目录是 `smb://host/share/path` ✓，
/// 而 `buildUrl()` **不写账号密码**（安全考虑 ✓）⇒ 之后读图/列目录只能拿到"无凭据"的 URL ✓
/// ⇒ 需要认证的共享会**静默走匿名连接** ✗（此前后者能用只是因为共享开了 guest ✓）。
/// 现在：URL 里没有凭据时回退到设置里保存的同 host+share 配置 ✓ ——
/// ⭐ **凭据永远不进 URL / 不进备份** ✓（只在本机内存里取用 ✓）。
///
/// [saved] 仅供**单元测试注入** ✓（生产调用传 null ⇒ 读 `appdata.settings['smbServers']` ✓）。
SmbConnection? _findSavedConnection(
  String host,
  String share, [
  List<dynamic>? saved,
]) {
  final raw = saved ?? appdata.settings['smbServers'];
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
SmbConfig parseSmbConfigFromUrl(String url, {List<dynamic>? savedServers}) {
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
  final saved = _findSavedConnection(uri.host, share, savedServers);
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
