import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';
import 'package:venera_nas/network/smb/smb_utils.dart';

/// SMB 配置 / URL 解析的专项测试 ✓（2026-10-24 目标轮 4 ✓）
///
/// 守护点（都是这轮真实改过、且曾经出过问题的地方 ✓）：
/// 1. 协议选项（signing / seal / version）能正确序列化 ✓ 且**老数据向后兼容** ✓
/// 2. `buildUrl()` **绝不写入账号密码** ✓（凭据安全 ✓）
/// 3. URL 无凭据时**按 host+share 回退**到已保存服务器 ✓（修掉"导入后变匿名"✗）
///
/// ⚠️ 本文件**不依赖**全局 `appdata`（通过 `savedServers` 注入 ✓）、不读写真实文件 ✗。
void main() {
  group('SmbConfig JSON', () {
    test('协议选项可完整往返', () {
      const config = SmbConfig(
        host: '192.168.1.10',
        port: 445,
        share: 'Comics',
        username: 'user',
        password: 'pass',
        domain: 'WORKGROUP',
        signing: true,
        seal: false,
        version: Smb2Version.v210,
      );
      final restored = SmbConfig.fromJson(config.toJson());
      expect(restored.host, config.host);
      expect(restored.share, config.share);
      expect(restored.username, config.username);
      expect(restored.password, config.password);
      expect(restored.domain, config.domain);
      expect(restored.signing, isTrue);
      expect(restored.seal, isFalse);
      expect(restored.version, Smb2Version.v210);
    });

    test('老版本 JSON（无协议选项）取默认值', () {
      final restored = SmbConfig.fromJson({
        'host': 'nas',
        'port': 445,
        'share': 'share',
        'username': 'u',
        'password': 'p',
        'domain': '',
      });
      expect(restored.signing, isFalse);
      expect(restored.seal, isFalse);
      expect(restored.version, Smb2Version.any);
    });

    test('未知方言名回退 any（不抛异常）', () {
      final restored = SmbConfig.fromJson({
        'host': 'nas',
        'share': 'share',
        'version': 'v9999',
      });
      expect(restored.version, Smb2Version.any);
    });

    test('buildUrl 绝不写入账号密码（凭据安全）', () {
      const config = SmbConfig(
        host: 'nas.local',
        share: 'Comics',
        username: 'user',
        password: 'secret',
      );
      final url = config.buildUrl('Series/Chapter 1/001.jpg');
      expect(url.startsWith('smb://nas.local/Comics/'), isTrue);
      expect(url.contains('user'), isFalse);
      expect(url.contains('secret'), isFalse);
      expect(url.contains('@'), isFalse);
    });

    test('buildUrl 非 445 端口写进 URL，且反斜杠转正斜杠', () {
      const config = SmbConfig(host: 'nas', port: 1445, share: 's');
      final url = config.buildUrl(r'dir\sub\file.jpg');
      expect(url, 'smb://nas:1445/s/dir/sub/file.jpg');
    });
  });

  group('parseSmbConfigFromUrl', () {
    test('URL 带 userinfo 时解析出账号密码', () {
      final config = parseSmbConfigFromUrl(
        'smb://user:pass@nas.local/share/dir/file.jpg',
        savedServers: const [],
      );
      expect(config.host, 'nas.local');
      expect(config.share, 'share');
      expect(config.username, 'user');
      expect(config.password, 'pass');
    });

    test('URL 无凭据且无已保存服务器 ⇒ 匿名 + 默认协议选项', () {
      final config = parseSmbConfigFromUrl(
        'smb://nas.local/share/dir/file.jpg',
        savedServers: const [],
      );
      expect(config.username, isEmpty);
      expect(config.password, isEmpty);
      expect(config.domain, isEmpty);
      expect(config.signing, isFalse);
      expect(config.seal, isFalse);
      expect(config.version, Smb2Version.any);
    });

    test('URL 无凭据时按 host+share 回退已保存服务器（含协议选项）', () {
      final saved = [
        SmbConnection(
          name: '我的 NAS',
          config: const SmbConfig(
            host: 'NAS.local',
            share: 'share',
            username: 'user',
            password: 'pass',
            domain: 'WORKGROUP',
            signing: true,
            seal: true,
            version: Smb2Version.any3,
          ),
        ).toJson(),
      ];
      final config = parseSmbConfigFromUrl(
        'smb://nas.local/share/dir/file.jpg',
        savedServers: saved,
      );
      expect(config.username, 'user');
      expect(config.password, 'pass');
      expect(config.domain, 'WORKGROUP');
      expect(config.signing, isTrue);
      expect(config.seal, isTrue);
      expect(config.version, Smb2Version.any3);
      // ⭐ 关键：凭据只在本机内存里取用，URL 本身仍然没有账号密码 ✓
      expect(
        const SmbConfig(host: 'nas.local', share: 'share').buildUrl(),
        isNot(contains('@')),
      );
    });

    test('share 不匹配时不回退', () {
      final saved = [
        SmbConnection(
          name: 'other',
          config: const SmbConfig(
            host: 'nas.local',
            share: 'other',
            username: 'u',
          ),
        ).toJson(),
      ];
      final config = parseSmbConfigFromUrl(
        'smb://nas.local/share/file.jpg',
        savedServers: saved,
      );
      expect(config.username, isEmpty);
    });

    test('损坏的单条配置不影响其它配置', () {
      final saved = <dynamic>[
        {'name': 'broken'},
        SmbConnection(
          name: 'ok',
          config: const SmbConfig(host: 'nas', share: 'share', username: 'u'),
        ).toJson(),
      ];
      final config = parseSmbConfigFromUrl(
        'smb://nas/share/x.jpg',
        savedServers: saved,
      );
      expect(config.username, 'u');
    });

    test('smbPathFromUrl 与 isSmbPath', () {
      expect(isSmbPath('smb://a/b/c'), isTrue);
      expect(isSmbPath('/local/path'), isFalse);
      expect(smbPathFromUrl('smb://host/share/dir/f.jpg'), 'dir/f.jpg');
      expect(smbPathFromUrl('smb://host/share'), isEmpty);
    });
  });

  group('sanitizeSmbPathCredentials（下载路径凭据剥离 ✓）', () {
    test('剥离账号密码，保留 host/share/子目录', () {
      expect(
        sanitizeSmbPathCredentials('smb://user:pass@nas.local/share/dir'),
        'smb://nas.local/share/dir',
      );
    });

    test('保留端口', () {
      expect(
        sanitizeSmbPathCredentials('smb://u:p@nas.local:1445/share'),
        'smb://nas.local:1445/share',
      );
    });

    test('本来没有凭据 ⇒ 原样返回', () {
      const path = 'smb://nas.local/share/dir';
      expect(sanitizeSmbPathCredentials(path), path);
    });

    test('非 SMB 路径 ⇒ 原样返回（不误伤本地路径）', () {
      expect(
        sanitizeSmbPathCredentials('/home/user/comics'),
        '/home/user/comics',
      );
      expect(sanitizeSmbPathCredentials('file:///tmp/x'), 'file:///tmp/x');
    });

    test('只有用户名没有密码也能剥离', () {
      expect(
        sanitizeSmbPathCredentials('smb://user@nas.local/share'),
        'smb://nas.local/share',
      );
    });
  });
}
