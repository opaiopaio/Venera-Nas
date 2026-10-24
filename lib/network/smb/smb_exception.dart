/// ⭐ 2026-10-26：SMB 层统一异常类型 ✓
///
/// 为什么不用裸 `String` ✗：`throw "..."` 让调用方无法按类型区分
/// "SMB 层自己抛出的可预期错误"与其它运行时错误 ✓；改为
/// `implements Exception` 后可以 `on SmbException catch` 统一处理 ✓。
///
/// ⚠️ [toString] **必须原样返回 [message]** ✗ —— 界面与日志多处直接
/// `e.toString()` 展示（如阅读页错误态 ✓），返回值一变就等于改了用户可见文案 ✓。
class SmbException implements Exception {
  const SmbException(this.message);

  final String message;

  @override
  String toString() => message;
}
