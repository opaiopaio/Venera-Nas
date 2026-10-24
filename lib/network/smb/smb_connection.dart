import 'dart:convert';

import 'package:dart_smb2/dart_smb2.dart';
// ⭐ 2026-10-25：`@visibleForTesting`（把 `hintFor` 暴露给单测 ✓）。
import 'package:flutter/foundation.dart' show visibleForTesting;

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
  /// 用户实测的两类真实问题（都是服务端限制，与账号密码无关 ✓）：
  /// 1. ⚠️ **加密（seal）可能不被服务器接受** ✗ ⇒ 协商阶段返回 `STATUS_NOT_SUPPORTED (0xc00000bb)` ✗
  /// 2. ⚠️ **签名（signing）可能不匹配** ✗ ⇒ `Wrong signature in received PDU` ✗
  /// ⚠️ 具体哪些服务器/固件会这样，取决于其实际版本与配置 ✓ —— 所以文案只说"可尝试关闭" ✓，
  /// 不点名、不下绝对结论 ✗。
  ///
  /// 本方法：先按**当前配置**试 ✓；失败就**逐项降级**再试 ✓（不改用户已保存的配置 ✗），
  /// 并把"哪一套参数能连"直接告诉用户 ✓ ⇒ 用户照提示改即可 ✓。
  /// ⭐ 2026-10-25：**诊断总预算 30s** ✓ —— 最多 1 次原配置 + 若干降级，
  /// 原先每项都 10s 且可能重复试同一套参数 ✗ ⇒ 用户能等 1 分钟以上 ✗。
  static const _diagnosisBudget = Duration(seconds: 30);

  /// 单次探测上限 ✓（与 [_diagnosisBudget] 共同约束总时长 ✓）。
  static const _probeTimeout = Duration(seconds: 10);

  Future<String?> testConnectionWithDiagnosis() async {
    final deadline = DateTime.now().add(_diagnosisBudget);
    final originalError = await _testWith(
      config,
      timeout: _timeoutWithin(deadline),
    );
    if (originalError == null) return null;

    final hint = _hintFor(originalError);

    // ⚠️ 只在"像是协议/签名/协商问题"时才逐项降级 ✓ ——
    // 否则连不上的主机（网络不通 ✓）会把同样的失败重试多次，用户要等几十秒 ✗。
    final lower = originalError.toLowerCase();
    final looksLikeProtocolIssue =
        originalError.contains('0xc00000bb') ||
        originalError.contains('STATUS_NOT_SUPPORTED') ||
        originalError.contains('0xc00000bc') ||
        lower.contains('negotiate') ||
        lower.contains('signature') ||
        lower.contains('seal') ||
        lower.contains('encrypt');
    if (!looksLikeProtocolIssue) {
      return '$originalError$hint';
    }

    // ⭐ 降级顺序（2026-10-25 按真实设备调整 ✓）：
    // 先把用户**只打开的那一项**单独关掉 ✓（最可能就是它 ✓），再逐级降版本 ✓。
    // ⭐ 2026-10-25：**按实际配置去重** ✓ —— 例如本来 signing 就是 false 时，
    // "关签名"与"签名加密都关闭"是同一套参数 ✗，重复试只会白等 10s ✓。
    final fallbacks = <MapEntry<String, SmbConfig>>[];
    final seen = <String>{_configKey(config)};
    void addFallback(String label, SmbConfig target) {
      if (seen.add(_configKey(target))) {
        fallbacks.add(MapEntry(label, target));
      }
    }

    if (config.signing) {
      addFallback('关闭「要求消息签名」（其它保持不变）', config.copyWith(signing: false));
    }
    if (config.seal) {
      addFallback('关闭「SMB3 加密」（其它保持不变）', config.copyWith(seal: false));
    }
    addFallback(
      '签名与加密都关闭（其它保持不变）',
      config.copyWith(signing: false, seal: false),
    );
    addFallback(
      '签名与加密都关闭，协商版本 = 自动',
      config.copyWith(signing: false, seal: false, version: Smb2Version.any),
    );
    addFallback(
      '签名与加密都关闭，协商版本 = SMB 3.0.2',
      config.copyWith(signing: false, seal: false, version: Smb2Version.v302),
    );
    addFallback(
      '签名与加密都关闭，协商版本 = SMB 2.1',
      config.copyWith(signing: false, seal: false, version: Smb2Version.v210),
    );

    var budgetExhausted = false;
    for (final entry in fallbacks) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        budgetExhausted = true;
        break;
      }
      final err = await _testWith(
        entry.value,
        timeout: _timeoutWithin(deadline),
      );
      if (err == null) {
        // ⭐ 2026-10-25（用户实测追问 ✓）：**降级项能连 = 实际可用** ✓
        // ⇒ 测试结果应报"连接成功（已自动降级 ✓）"，而不是把"原配置失败"当结论 ✗
        //（实际读图/下载也会自动走同一条降级链 ✓，这套参数就是**真实生效**的 ✓）。
        return '✅ 连接成功 ✓（已自动降级为：${entry.key}）\n'
            '实际读图 / 下载会自动使用这套参数 ✓；'
            '建议按这套设置**保存一次** ✓（以后少一次试错 ✓）。';
      }
    }

    final budgetNote = budgetExhausted
        ? '\n\n⏱ 诊断总时长已达 ${_diagnosisBudget.inSeconds} 秒，剩余降级项未再尝试 ✓'
              '（可先按上面的单项提示手动调整 ✓）。'
        : '';
    return '$originalError$hint\n\n'
        '❌ 自动降级（关签名 / 关加密 / 自动版本 / 3.0.2 / 2.1）也连不上 ✗$budgetNote\n'
        '请检查：① 服务器是否**只启用了 SMB1**（本应用不支持 SMB1 ✗）\n'
        '② 共享名与账号密码 ✓ ③ 端口是否为 445 ✓';
  }

  /// 在总预算内给单次探测分配时长 ✓（至少 1s，避免 0 时长造成假超时 ✓）。
  static Duration _timeoutWithin(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return const Duration(seconds: 1);
    }
    return remaining < _probeTimeout ? remaining : _probeTimeout;
  }

  /// 参数指纹 ✓（[SmbConfig] 的 `==` 只比较 host/port/share/user ✓，
  /// 不足以判断"降级项是否重复" ✗，所以这里显式带上协议选项 ✓）。
  static String _configKey(SmbConfig c) =>
      '${c.host}|${c.port}|${c.share}|${c.username}|${c.password}|'
      '${c.domain}|${c.signing}|${c.seal}|${c.version.name}';

  /// 常见 SMB 错误码/错误文本 → 中文提示 ✓（只做提示 ✓，不改变连接行为 ✓）。
  ///
  /// ⚠️ 文案原则（2026-10-25 ✓）：**不点名具体实现、不下绝对结论** ✗ ——
  /// 只说"可能是…，可尝试…" ✓（具体原因需按服务器实际版本判断 ✓）。
  @visibleForTesting
  static String hintFor(String message) {
    bool has(String s) => message.contains(s);
    final lower = message.toLowerCase();
    if (lower.contains('wrong signature') ||
        has('STATUS_INVALID_SIGNATURE') ||
        lower.contains('signature')) {
      return '\n（签名校验未通过：可能是服务器与客户端的签名算法不匹配 ✓ '
          '—— 可尝试关闭「要求消息签名」✓）';
    }
    if (has('0xc00000bb') || has('STATUS_NOT_SUPPORTED')) {
      return '\n（该错误码通常表示：**服务器不接受**所选的 SMB 版本或加密 ✓ —— '
          '可尝试把协商版本改成「自动」，或关闭「SMB3 加密」✓）';
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

  static String _hintFor(String message) => hintFor(message);

  Future<String?> _testWith(
    SmbConfig target, {
    Duration timeout = _probeTimeout,
  }) async {
    // ⚠️ 2026-10-24：底层库无端口参数 ⇒ 非 445 端口无法测试，直接给出明确原因 ✓（不再静默失败 ✗）。
    if (target.port != 445) {
      return '端口 ${target.port} 暂不支持：底层库仅支持 445 端口。';
    }
    // 原生 connect 超时只接受秒 ✓；严格限制在 1~10s ✓（预算更短时按预算走 ✓）。
    final seconds = timeout.inSeconds < 1
        ? 1
        : (timeout.inSeconds > 10 ? 10 : timeout.inSeconds);
    Smb2Pool? pool;
    try {
      pool = await Smb2Pool.connect(
        host: target.host,
        share: target.share,
        user: target.username,
        password: target.password,
        domain: target.domain,
        timeoutSeconds: seconds,
        workers: 1,
        // ⭐ 2026-10-24：协议选项透传 ✓（与正式连接保持一致 ✓，避免"测试通过但实际连不上" ✗）。
        signing: target.signing,
        seal: target.seal,
        version: target.version,
      );
      // 列表操作也要受本次探测预算约束 ✓（服务器可能接受连接却不回目录 ✓）。
      await pool.listDirectory('').timeout(timeout);
      return null;
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
    } on Exception catch (e) {
      // ⭐ 只兜 Exception ✓：Error（断言/类型错误等）应继续上抛 ✓，
      // 否则会把程序缺陷伪装成"连接失败" ✗。
      return e.toString();
    } finally {
      if (pool != null) {
        try {
          // ⚠️ disconnect 失败不能覆盖上面的连接结论 ✗ ——
          // 原先 finally 里直接 await，断开异常会盖掉 "连接成功/具体失败原因" ✗。
          await pool.disconnect();
        } catch (_) {
          // 探测已经结束，断开失败只影响资源回收 ✓。
        }
      }
    }
  }
}
