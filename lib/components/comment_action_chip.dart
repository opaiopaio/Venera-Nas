part of 'components.dart';

/// 评论「回复数」与「点赞」的**描边胶囊唯一实现** ✓。
///
/// ⚠️ 逐项 1:1 复现原页面代码（**外观零变化** ✓）：外层 `Padding(left: AppSpace.sm)` ✓；
/// `Button.outlined` 无底色（`fillColor: Colors.transparent`）✓、文字色取继承默认色 ✓、
/// 圆角 `AppRadius.xl` ✓、`constraints` 让高度由内容决定 ✓、内边距 h:md / v:xs ✓、
/// 描边沿用 `outlined` 默认（outlineVariant 0.6 ✓）；内容为
/// `Row(mainAxisSize: min) -> [icon, SizedBox(width: 8), Text(text)]` ✓。
///
/// ⚠️ **加载态/选中态由调用方通过 `icon` 传入** ✓（例如 16×16 的 `CircularProgressIndicator`
/// ✓ 或 `favorite` 实心图标 ✓）—— 刻意**不用** `Button.isLoading` ✗：它替换的是**整个**
/// `child`（含数字）✗，与两页现状（只换左侧图标 ✓）不符 ✓。
class CommentActionChip extends StatelessWidget {
  const CommentActionChip({
    required this.icon,
    required this.text,
    required this.onPressed,
    super.key,
  });

  /// 左侧图标：加载态 / 已点赞态由调用方按现状构造后传入 ✓。
  final Widget icon;

  /// 右侧文字（回复数 / 点赞数 ✓）。
  final String text;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.sm),
      child: Button.outlined(
        fillColor: Colors.transparent,
        textColor: DefaultTextStyle.of(context).style.color,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        constraints: const BoxConstraints(
          minHeight: 0,
          maxHeight: double.infinity,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [icon, const SizedBox(width: 8), Text(text)],
        ),
      ),
    );
  }
}
