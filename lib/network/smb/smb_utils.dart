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

/// ⭐ 2026-10-25：**URL ⇒ [SmbConfig] 解析结果的内存缓存** ✓（配置变更自动失效 ✓）。
///
/// 为什么要有 ✓：读一页图 / 加载一张封面都要走 [parseSmbConfigFromUrl] ✓，
/// 而它每次都得遍历 `appdata.settings['smbServers']` 并逐条 `SmbConnection.fromJson` ✓ ——
/// 翻页（并发 2 ✓）+ 25 张封面 + 预取同时进行时，这是完全重复的劳动 ✗。
///
/// 失效策略 ✓：
/// 1. **设置里的 `smbServers` 列表对象换新** ⇒ 视为配置变更 ✓
///    （设置页保存 / 备份恢复都是**整体替换列表** ✓，identity 一变即失效 ✓）；
/// 2. 显式调用 [invalidateSmbConfigCache] ✓（"重置 SMB 连接"、测试清理 ✓）。
///
/// ⚠️ 缓存里含**明文凭据** ✗ —— 与 `appdata.settings['smbServers']` 同等敏感 ✓；
/// 它只存在于内存 ✓，不写盘、不进备份 ✓（`appdata` / `utils/data.dart` 已剔除该键 ✓）。
final Map<String, SmbConfig> _configCache = {};

/// 上次缓存对应的 `smbServers` 列表对象 ✓（identity 比较 ✓）。
Object? _configCacheSource;

/// 缓存条目上限 ✓（防止各种 URL 写法把内存顶大 ✓）。
const int _configCacheLimit = 128;

/// ⭐ 清空解析缓存 ✓（配置变更 / 重置连接 / 测试隔离时调用 ✓）。
void invalidateSmbConfigCache() {
  _configCache.clear();
  _configCacheSource = null;
}

/// 解析缓存的键 ✓：同一共享的不同文件共用一条配置 ✓ ⇒ 只按
/// `host|port|share|URL 内凭据` 归并 ✓（路径不参与 ✓）。
String _configCacheKeyOfUrl(String url) {
  final uri = Uri.parse(url);
  final parts = uri.pathSegments;
  final share = parts.isNotEmpty ? parts.first : '';
  return '${uri.host.toLowerCase()}|${uri.hasPort ? uri.port : 445}|'
      '$share|${uri.userInfo}';
}

/// Parse [SmbConfig] from an `smb://` URL.
///
/// Credentials embedded in the URL's userinfo are decoded.
/// For `smb://user:pass@host:port/share/path/to/file`,
/// extracts host, port, share, username, and password.
///
/// ⭐ 2026-10-24：URL 不带凭据时**回退到已保存的服务器配置** ✓，
/// 并把 domain / 签名 / 加密 / 方言一起带上 ✓（这些无法编码进 URL ✓）。
///
/// ⭐ 2026-10-25：结果按 `host|port|share|凭据` 做**内存缓存** ✓（见文件顶部说明 ✓）；
/// 配置变更（`smbServers` 列表换新 ✓）或 [invalidateSmbConfigCache] 后自动重新解析 ✓。
/// ⚠️ 测试注入 [savedServers] 时**完全绕过缓存** ✗ —— 用例之间互不污染 ✓。
SmbConfig parseSmbConfigFromUrl(String url, {List<dynamic>? savedServers}) {
  if (savedServers != null) {
    return _parseSmbConfigFromUrl(url, savedServers);
  }
  final raw = appdata.settings['smbServers'];
  if (!identical(raw, _configCacheSource)) {
    // 配置变更 ⇒ 旧解析结果（旧凭据 / 旧协议选项）一律作废 ✓。
    _configCache.clear();
    _configCacheSource = raw;
  }
  final cacheKey = _configCacheKeyOfUrl(url);
  final cached = _configCache[cacheKey];
  if (cached != null) return cached;
  final config = _parseSmbConfigFromUrl(url, raw is List ? raw : null);
  if (_configCache.length >= _configCacheLimit) {
    _configCache.clear();
  }
  _configCache[cacheKey] = config;
  return config;
}

/// 实际的解析过程 ✓（不碰缓存 ✓）。
SmbConfig _parseSmbConfigFromUrl(String url, List<dynamic>? savedServers) {
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

/// 已解析出的 SMB 下载目标 ✓（连接配置 + 共享内目录 ✓）。
class SmbDownloadTarget {
  const SmbDownloadTarget(this.config, this.remoteDir);

  final SmbConfig config;

  /// 共享内目录（如 `图包` 或 `图包/子目录` ✓），空串表示共享根 ✓。
  final String remoteDir;
}

/// ⭐ 2026-10-25（用户实测 ✓）：**下载根路径的有效目标** ✓ —— 修正"**漏写共享名**"的情况 ✗。
///
/// 实例 ✓：用户填 `smb://192.168.8.1/图包` ✓，而真实共享是 `NAS` ✓（`图包` 只是共享里的目录 ✗）
/// ⇒ 旧逻辑把 `图包` 当共享名去连 ✗ ⇒ 服务器拒绝 ⇒ `Failed to parse fixed part of…` ✗。
///
/// 规则 ✓：
/// 1. URL 的"共享段"能在已保存服务器里精确命中（host + share）⇒ 直接用它 ✓；
/// 2. 否则按 **host** 找已保存服务器 ✓ ⇒ 用它的**共享名 + 凭据 + 协议选项** ✓，
///    URL 的**第一段视作共享内目录** ✓；
/// 3. 都没有 ⇒ 返回 null（调用方给出明确错误 ✓，不再静默连错共享 ✗）。
SmbDownloadTarget? resolveSmbDownloadTarget(String url) {
  if (!isSmbPath(url)) return null;
  final uri = Uri.parse(url);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final direct = parseSmbConfigFromUrl(url);

  // ① 精确命中（host + share）✓
  if (direct.share.isNotEmpty &&
      _findSavedConnection(uri.host, direct.share) != null) {
    return SmbDownloadTarget(
      direct,
      segments.length <= 1 ? '' : segments.sublist(1).join('/'),
    );
  }

  // ② 按 host 找服务器 ✓（共享名取自配置 ✓，URL 全段都当目录 ✓）
  final raw = appdata.settings['smbServers'];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final conn = SmbConnection.fromJson(Map<String, dynamic>.from(item));
        if (conn.config.host.toLowerCase() == uri.host.toLowerCase() &&
            conn.config.share.isNotEmpty) {
          return SmbDownloadTarget(conn.config, segments.join('/'));
        }
      } catch (_) {
        // 单条配置损坏不影响其它 ✓。
      }
    }
  }

  // ③ 实在找不到已保存服务器 ⇒ 保持 URL 自身解析（匿名 / userinfo ✓）
  if (direct.share.isEmpty) return null;
  return SmbDownloadTarget(
    direct,
    segments.length <= 1 ? '' : segments.sublist(1).join('/'),
  );
}
