import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

/// ⭐ 本轮（用户实测反馈 ✓）回归守护：**选项框（`Select`）不得撑满它所在的行**。
///
/// 用户原话：这个选项式按钮框"**紧紧贴住遮罩的上下边框**"，希望"高度缩小一些" ✓。
/// 真因 ✓：`Button` 内部的内容盒用了 `Center(widthFactor: 1)`（`heightFactor` 为 `null` ✗）⇒
/// 只要父级给了**有界**高度（设置行是 `ListTile.trailing` ⇒ 行高 56 ✓），
/// `Center` 就会撑满父级高度 ✗ —— 而 `Select` 传的 `maxHeight: infinity`
/// 本意正是"高度由内容决定" ✓（见 `lib/components/select.dart` 与 `lib/components/button.dart` ✓）。
/// 修法 ✓：`button.dart` 的内容盒改为 `Center(widthFactor: 1, heightFactor: 1, …)` ✓。
///
/// 本文件锁三条不变量 ✓：
/// ① `Select` 在设置行里**比行矮**（回到重构前的内容高度 ✓）；
/// ② "高度由内容决定"的按钮在有界父级里**不撑满** ✓；
/// ③ 默认按钮（高度被约束钉死）**高度不受影响** ✓。
void main() {
  const tileHeight = 56.0; // ListTile 单行高度（线上设置行 ✓）

  testWidgets('T-BH1 Select 在设置行里比行矮，不贴遮罩上下边', (tester) async {
    await tester.pumpWidget(
      _host(
        ListTile(
          title: const Text('Theme mode'),
          trailing: Select(
            current: 'System',
            values: const ['System', 'Light', 'Dark'],
            minWidth: 64,
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileH = tester.getSize(find.byType(ListTile)).height;
    final selectH = tester.getSize(find.byType(Select)).height;
    expect(tileH, tileHeight, reason: '测试上下文应复刻线上设置行高');
    expect(selectH, lessThan(tileH), reason: '选项框撑满了整行 ⇒ 会贴住遮罩上下边（用户实测反馈 ✗）');
    // 内容高度 = 图标（AppIconSize.lg）+ 上下内边距（AppSpace.xs ×2）+ 描边（1 ×2 ✓，容差 2 ✓）。
    expect(
      selectH,
      closeTo(AppIconSize.lg + 2 * AppSpace.xs, 2),
      reason: '选项框高度应回到"由内容决定"（重构前的观感 ✓）',
    );
  });

  testWidgets('T-BH2 高度由内容决定的按钮在有界父级里不撑满', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 80,
          child: Center(
            child: Button.outlined(
              fillColor: Colors.transparent,
              constraints: const BoxConstraints(
                minHeight: 0,
                maxHeight: double.infinity,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.xs,
              ),
              onPressed: () {},
              child: const Text('v'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttonH = tester.getSize(find.byType(Button)).height;
    expect(
      buttonH,
      lessThan(80),
      reason: '传无界 maxHeight 的按钮被父级高度撑满了 ⇒ "高度由内容决定"失效',
    );
    expect(buttonH, greaterThanOrEqualTo(2 * AppSpace.xs));
  });

  testWidgets('T-BH3 默认按钮（高度被约束钉死）高度不受影响', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 80,
          child: Center(
            child: Button.normal(onPressed: () {}, child: const Text('OK')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(Button)).height,
      AppIconSize.lg + AppSpace.sm,
      reason: '默认胶囊按钮的高度规范是 32 且被约束钉死 ⇒ 不应随父级高度变化',
    );
  });

  testWidgets('T-BH4 评论/点赞描边胶囊同样不撑满定高行', (tester) async {
    // 与 `Select` 同款："传无界 maxHeight 表示高度由内容决定" ✓
    //（线上上下文见 `comments_page.dart` 的 `SizedBox(height: 36)` ✓）。
    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 36,
          child: Row(
            children: [
              CommentActionChip(
                icon: const Icon(Icons.favorite, size: AppIconSize.xs),
                text: '12',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(CommentActionChip)).height,
      lessThan(36),
      reason: '描边胶囊被定高行撑满 ⇒ 与"高度由内容决定"不符',
    );
  });
}

/// `Button` 的底色分支会读 `AppSettingsScope` ✓（`button.dart` 的 `buttonColor` ✓）⇒ 必须提供 ✓。
Widget _host(Widget child) => AppSettingsScope(
  child: MaterialApp(home: Scaffold(body: child)),
);
