import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/components/components.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// 二级页面**统一表面** `SecondaryPageSurface` 的语义回归（见 doc-private 12 号文档）。
///
/// 锁死两条使用路径的差异，防止将来"顺手统一"把语义改坏：
/// - `ContentDialog`（默认）：**补主题表面色 + 裁剪圆角**（否则弹窗会透出下层内容 ✗）
/// - `PopUpWidgetScaffold`（`fallbackToSurface: false, clip: false`）：
///   形状/底色由**自身路由的 decoration** 负责（`PopUpWidget.buildPage`），表面不得再补 ✗
void main() {
  Future<void> pumpSurface(WidgetTester tester, Widget surface) async {
    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: surface)),
      ),
    );
  }

  /// 置为「二级页面体系关闭」→ `secondaryPageDecoration()`/`customSecondarySurfaceColor()`
  /// 均返回 null，从而让"是否补主题表面色"这一点可确定性断言。
  void disableSecondaryPageFeature() {
    final old = appdata.settings['secondaryPageMode'];
    addTearDown(() => appdata.settings['secondaryPageMode'] = old);
    appdata.settings['secondaryPageMode'] = 'off';
  }

  testWidgets('默认（ContentDialog 路径）：补主题表面色 + 裁剪圆角', (tester) async {
    disableSecondaryPageFeature();
    await pumpSurface(
      tester,
      const SecondaryPageSurface(child: SizedBox(width: 80, height: 40)),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(surface, findsOneWidget);
    expect(
      find.descendant(of: surface, matching: find.byType(ClipRRect)),
      findsOneWidget,
      reason: '默认应裁剪圆角（ContentDialog 需要）',
    );
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsWidgets,
      reason: '体系关闭时应补主题表面色，避免弹窗透出下层内容',
    );
  });

  testWidgets('PopUpWidgetScaffold 路径：不裁剪、不补底（形状与底色由路由 decoration 负责）', (
    tester,
  ) async {
    disableSecondaryPageFeature();
    await pumpSurface(
      tester,
      const SecondaryPageSurface(
        clip: false,
        fallbackToSurface: false,
        child: SizedBox(width: 80, height: 40),
      ),
    );
    final surface = find.byType(SecondaryPageSurface);
    expect(
      find.descendant(of: surface, matching: find.byType(ClipRRect)),
      findsNothing,
      reason: 'PopUpWidgetScaffold 的圆角由路由 decoration/Clip.antiAlias 提供',
    );
    expect(
      find.descendant(of: surface, matching: find.byType(ColoredBox)),
      findsNothing,
      reason: 'PopUpWidgetScaffold 不得自行补底色（会盖住路由 decoration 的观感）',
    );
  });
}
