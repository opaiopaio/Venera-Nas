import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_config.dart';

/// `SmbConfig.copyWith` 的测试 ✓（2026-10-25 ✓）
///
/// 用途：**测试连接自动诊断**会用它逐项降级试参数 ✓
///（自动版本 / 关闭加密 / 关闭签名 ✓）—— 必须保证"只改指定字段、其它保持原样" ✓。
void main() {
  test('copyWith 只覆盖指定字段，其余保持不变', () {
    const base = SmbConfig(
      host: 'nas.local',
      share: 'share',
      username: 'u',
      password: 'p',
      domain: 'WORKGROUP',
      signing: true,
      seal: true,
      version: Smb2Version.v311,
    );
    final copy = base.copyWith(version: Smb2Version.any, seal: false);
    expect(copy.host, 'nas.local');
    expect(copy.share, 'share');
    expect(copy.username, 'u');
    expect(copy.password, 'p');
    expect(copy.domain, 'WORKGROUP');
    expect(copy.signing, isTrue, reason: '未指定 signing ⇒ 保持原值');
    expect(copy.seal, isFalse);
    expect(copy.version, Smb2Version.any);
  });

  test('copyWith 不带参数 ⇒ 等效副本', () {
    const base = SmbConfig(host: 'nas', share: 's', version: Smb2Version.v302);
    final copy = base.copyWith();
    expect(copy.host, base.host);
    expect(copy.share, base.share);
    expect(copy.port, base.port);
    expect(copy.version, base.version);
    expect(copy.signing, base.signing);
    expect(copy.seal, base.seal);
  });
}
