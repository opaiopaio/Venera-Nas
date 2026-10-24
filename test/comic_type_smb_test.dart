import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/comic_type.dart';

/// SMB 类型映射的回归测试 ✓（2026-10-24 目标轮 7 ✓）
///
/// 守护的真实 bug（历史文档记录过 ✓）：
/// > 「删除 SMB 历史条目时类型算错」—— 当时用 `ComicType('smb'.hashCode)` 当类型 ✗，
/// > 而实际存进库里的是 `ComicType.smb(-1)` ✓ ⇒ **删不掉** ✗。
/// 现在：必须走 `fromKey('smb')` ✓ / `fromHistorySourceKey('smb')` ✓，值恒为 `-1` ✓。
void main() {
  group('ComicType 内置类型', () {
    test('local = 0，smb = -1（历史/收藏/本地库三处共用 ✓）', () {
      expect(ComicType.local.value, 0);
      expect(ComicType.smb.value, -1);
    });

    test('fromKey 对 local / smb 返回内置类型（不是 hashCode ✗）', () {
      expect(ComicType.fromKey('local'), ComicType.local);
      expect(ComicType.fromKey('smb'), ComicType.smb);
      expect(ComicType.fromKey('smb').value, -1);
    });

    test('sourceKey 反向映射', () {
      expect(ComicType.local.sourceKey, 'local');
      expect(ComicType.smb.sourceKey, 'smb');
    });

    test('fromHistorySourceKey 覆盖历史里的三种写法', () {
      // 正常源 key
      expect(ComicType.fromHistorySourceKey('local'), ComicType.local);
      expect(ComicType.fromHistorySourceKey('smb'), ComicType.smb);
      // 未知源兜底格式 `Unknown:<value>`
      expect(ComicType.fromHistorySourceKey('Unknown:-1'), ComicType.smb);
      expect(ComicType.fromHistorySourceKey('Unknown:5'), const ComicType(5));
    });

    test('未知网络源仍退回 hashCode 口径（保持旧行为 ✓）', () {
      const key = 'some_network_source';
      expect(ComicType.fromHistorySourceKey(key).value, key.hashCode);
    });

    test('非法 Unknown 格式不至于抛异常（退回 fromKey ✓）', () {
      expect(
        () => ComicType.fromHistorySourceKey('Unknown:not_a_number'),
        returnsNormally,
      );
    });
  });
}
