import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';

/// SMB 错误提示的测试 ✓（2026-10-25 ✓）
///
/// 背景：用户实测 **KSMBd（路由器内核 SMB3 服务端）** 的两个坑 ✓：
/// - 开「要求消息签名」⇒ `Wrong signature in received PDU` ✗
/// - 开「SMB3 加密」⇒ `SMB2_STATUS_NOT_SUPPORTED (0xc00000bb)` ✗
/// ⇒ 提示必须让用户看懂"该关哪一项" ✓（而不是只丢一串英文错误码 ✗）。
void main() {
  test('签名不兼容』提示指向"关闭签名"', () {
    final hint = SmbConnection.hintFor(
      'Connect failed: smb2_service failed with : Wrong signature in received PDU',
    );
    expect(hint, contains('签名'));
    expect(hint, contains('关闭'));
  });

  test('STATUS_NOT_SUPPORTED 提示指向"版本或加密"', () {
    final hint = SmbConnection.hintFor(
      'Negotiate failed with (0xc00000bb) SMB2_STATUS_NOT_SUPPORTED',
    );
    expect(hint, contains('不支持'));
  });

  test('账号密码错误提示', () {
    expect(
      SmbConnection.hintFor('0xc000006d STATUS_LOGON_FAILURE'),
      contains('账号或密码'),
    );
  });

  test('无权限提示', () {
    expect(
      SmbConnection.hintFor('0xc0000022 STATUS_ACCESS_DENIED'),
      contains('无权'),
    );
  });

  test('共享名不存在提示', () {
    expect(
      SmbConnection.hintFor('0xc00000cc STATUS_BAD_NETWORK_NAME'),
      contains('共享名'),
    );
  });

  test('未知错误不给误导性提示', () {
    expect(SmbConnection.hintFor('some random failure'), isEmpty);
  });
}
