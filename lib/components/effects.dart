part of 'components.dart';

class BlurEffect extends StatelessWidget {
  final Widget child;

  final double blur;

  final BorderRadius? borderRadius;

  const BlurEffect({
    required this.child,
    this.borderRadius,
    this.blur = 15,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // ⭐ C6-新①（用户要求 ✓，2026-10-09）：用户明确表示**不喜欢毛玻璃** ✗，并指出
    // "原版毛玻璃的位置很突兀，并不好看" ✓，原话："**不是禁用，全部移除都可以**" ✓
    // → 因此这里改为**彻底直通**（只返回 `child` ✓）：任何情况都不再模糊 ✓。
    //
    // 这样做的两个理由 ✓：
    // ① 覆盖全部 6 个调用点 ✓（`menu.dart` / `flyout.dart` / `reader/scaffold.dart` ×2 /
    //    `comic_details_page/cover_viewer.dart` / `image_favorites_page/image_favorites_photo_view.dart` ✓）
    //    —— 不必逐个拆嵌套括号 ✗，零结构性风险 ✓；
    // ② 类名与参数**原样保留** ✓ → 将来若只想恢复某一处毛玻璃，改这里一处即可 ✓
    //    （原始实现见 git 历史：`ClipRRect + BackdropFilter + ImageFilter.blur` ✓）。
    //
    // 注 ✓：原先"有自定义背景时不模糊"（`backgroundFeatureActive` ✓）的开关因此失去意义 ✓ ——
    // 现在是**任何情况都不模糊** ✓，`AppSettingsScope.of(context)` 依赖也一并去掉 ✓
    //（本控件已不随任何设置变化 ✓，少一处无谓重建 ✓）。
    return child;
  }
}
