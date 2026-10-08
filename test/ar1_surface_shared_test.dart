import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/window_overlay.dart';

/// **T-AR1**：菜单与二级页面**共用同一实现**的行为回归测试。
///
/// 用户 2026-10-09 的要求是"把菜单的样式和背景也**照二级页面弹窗复刻上去**
///（透明/不透明，变暗/变浅）"。为了让"复刻"是**真同构**（而不是两套代码迟早漂移），
/// 实现上把色调合成抽成了 [secondarySurfaceColorFor]，由两边共用。
///
/// 本用例就用来**钉死这一点**：同设置下，
/// `customSecondarySurfaceColor(scheme)`（二级页面路径）与直接调用共用函数的结果
/// 必须**完全相等**；同时覆盖 不透明/半透明/关闭 与 变暗/变浅/无色调 的典型组合。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00BCD4));

  /// 把二级页面与菜单两侧设置成同一组值，以便比较两条路径。
  void setBothSides({
    required String mode,
    required String tint,
    required double strength,
  }) {
    appdata.settings['secondaryPageFollowTheme'] = false;
    appdata.settings['secondaryPageMode'] = mode;
    appdata.settings['secondaryPageTint'] = tint;
    appdata.settings['secondaryPageTintStrength'] = strength;
    appdata.settings['menuSurfaceMode'] = mode;
    appdata.settings['menuSurfaceTint'] = tint;
    appdata.settings['menuSurfaceTintStrength'] = strength;
  }

  tearDown(() {
    // 不留副作用
    appdata.settings['secondaryPageFollowTheme'] = true;
    appdata.settings['menuSurfaceMode'] = 'opaque';
    appdata.settings['menuSurfaceTint'] = 'darken';
    appdata.settings['menuSurfaceTintStrength'] =
        AppOpacity.tintStrengthDefault;
  });

  test('T-AR1：同设置下二级页面路径与共用函数结果完全相等', () {
    const combos = <List<Object>>[
      ['opaque', 'darken', 0.22],
      ['opaque', 'lighten', 0.22],
      ['transparent', 'darken', 0.22],
      ['transparent', 'lighten', 0.10],
      ['opaque', 'none', 0.22],
      ['off', 'darken', 0.22],
    ];
    for (final c in combos) {
      final mode = c[0] as String;
      final tint = c[1] as String;
      final strength = (c[2] as num).toDouble();
      setBothSides(mode: mode, tint: tint, strength: strength);

      final viaSecondaryPage = customSecondarySurfaceColor(scheme);
      final viaShared = secondarySurfaceColorFor(
        scheme: scheme,
        mode: mode,
        tint: tint,
        strength: strength,
      );

      // 注意：`off` 时二级页面路径被门禁拦下返回 null（这是它的既有语义）；
      // 其余情况两者必须逐位相等 —— 这正是"共用同一实现"的证明。
      if (mode == 'off') {
        expect(viaSecondaryPage, isNull, reason: 'off 时二级页面路径应返回 null（门禁语义）');
        continue;
      }
      expect(
        viaSecondaryPage,
        viaShared,
        reason:
            '菜单与二级页面结果不一致（mode=$mode tint=$tint strength=$strength）'
            '→ 说明"复刻"已漂移成两套实现',
      );
    }
  });

  test('T-AR1：strength 超出范围时被钳制（与二级页面同规则）', () {
    setBothSides(mode: 'opaque', tint: 'darken', strength: 5.0);
    expect(
      customSecondarySurfaceColor(scheme),
      secondarySurfaceColorFor(
        scheme: scheme,
        mode: 'opaque',
        tint: 'darken',
        strength: 5.0,
      ),
    );
    setBothSides(mode: 'opaque', tint: 'darken', strength: -1.0);
    expect(
      customSecondarySurfaceColor(scheme),
      secondarySurfaceColorFor(
        scheme: scheme,
        mode: 'opaque',
        tint: 'darken',
        strength: -1.0,
      ),
    );
  });
}
