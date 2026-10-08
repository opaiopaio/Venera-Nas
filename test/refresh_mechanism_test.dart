import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/window_overlay.dart';

/// 刷新机制回归测试（见 ../workspace/archive/doc-private-legacy-20261009/03-implementation/11-refresh-mechanism.md）。
///
/// 证明核心链路：**设置变化 → `AppSettingsScope` 通知 → 依赖它的控件被框架重建**。
/// 这条链路取代了历史上 `App.forceRebuild()` 的"遍历整棵 element 树
/// markNeedsBuild()"做法（那会导致"页面切成左右两半、中间背景可滚动"的严重渲染 bug）。
void main() {
  testWidgets('设置变化 → 依赖 AppSettingsScope 的控件重建（外观即时生效）', (tester) async {
    final oldColor = appdata.settings['windowOverlayColor'];
    final oldOpacity = appdata.settings['windowOverlayOpacity'];
    // ⭐ N1：本测试验证"**自定义**遮罩色"的刷新链路 ✓ → 先关掉「跟随系统主题」总开关 ✓
    //（它默认 true ✓，开启时遮罩不参与、`windowOverlayColor()` 恒为透明 ✓ → 断言会失去意义 ✗）。
    final oldFollow = appdata.settings['windowOverlayFollowTheme'];
    addTearDown(() {
      appdata.settings['windowOverlayColor'] = oldColor;
      appdata.settings['windowOverlayOpacity'] = oldOpacity;
      appdata.settings['windowOverlayFollowTheme'] = oldFollow;
    });
    appdata.settings['windowOverlayFollowTheme'] = false;

    appdata.settings['windowOverlayColor'] = '#FF0000';
    appdata.settings['windowOverlayOpacity'] = 1.0;

    // 一个最小的"自己从设置算外观"的控件（与真实控件同样的依赖姿势）
    Widget app() => AppSettingsScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            AppSettingsScope.of(context); // ← 建立依赖
            return Text(
              '${windowOverlayColor().toARGB32()}',
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
    );

    await tester.pumpWidget(app());
    final before = tester.widget<Text>(find.byType(Text)).data;
    expect(before, isNotNull);

    // 改设置（`[]=` 内部会 notifyListeners）→ 依赖者应被重建、外观即时变化
    appdata.settings['windowOverlayColor'] = '#0000FF';
    await tester.pump();

    final after = tester.widget<Text>(find.byType(Text)).data;
    expect(
      after,
      isNot(equals(before)),
      reason: '设置变化后依赖 AppSettingsScope 的控件未被重建 → 刷新链路断了',
    );
  });

  testWidgets('没有建立依赖的控件不会被重建（对照组，说明依赖是必须的）', (tester) async {
    final oldColor = appdata.settings['windowOverlayColor'];
    addTearDown(() => appdata.settings['windowOverlayColor'] = oldColor);

    appdata.settings['windowOverlayColor'] = '#FF0000';
    var buildCount = 0;

    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              buildCount++; // 没有调用 AppSettingsScope.of(context)
              return const Text('static', textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );
    final countAfterFirstBuild = buildCount;

    appdata.settings['windowOverlayColor'] = '#0000FF';
    await tester.pump();

    expect(
      buildCount,
      countAfterFirstBuild,
      reason: '未建立依赖却重建了 —— 说明测试没有真正验证"依赖驱动"这一点',
    );
  });
}
