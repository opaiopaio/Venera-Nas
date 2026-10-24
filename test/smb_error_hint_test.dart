import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/network/smb/smb_connection.dart';

/// SMB 错误提示的测试 ✓（2026-10-25 ✓）
///
/// 背景：实测中确认了两类"服务端不接受签名/加密"的情况 ✓：
/// - 开「要求消息签名」⇒ `Wrong signature in received PDU` ✗
/// - 开「SMB3 加密」⇒ `SMB2_STATUS_NOT_SUPPORTED (0xc00000bb)` ✗
///
/// ⚠️ 文案要求（2026-10-25 ✓）：**不点名具体实现、不下绝对结论** ✗ ——
/// 只说"可能是…，可尝试关闭/改自动" ✓（本测试只断言"用户能看懂该改哪一项" ✓）。
void main() {
  test('签名相关错误提示指向"关闭签名"', () {
    final hint = SmbConnection.hintFor(
      'Connect failed: smb2_service failed with : Wrong signature in received PDU',
    );
    expect(hint, contains('签名'));
    expect(hint, contains('关闭'));
  });

  test('STATUS_NOT_SUPPORTED 提示给出"改自动 / 关加密"两个方向', () {
    final hint = SmbConnection.hintFor(
      'Negotiate failed with (0xc00000bb) SMB2_STATUS_NOT_SUPPORTED',
    );
    expect(hint, anyOf(contains('版本'), contains('加密')));
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
