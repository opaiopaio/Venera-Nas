import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

/// 外观令牌层的不变量测试（P3）。
///
/// 只测令牌本身的稳定性，保证"规则地基"不被无意改动；
/// 涉及 `appdata` 的行为测试（遮罩色合成、直角=0、全局文字零干预）需要设置层测试脚手架，
/// 见 `doc-private/08-tech-debt.md` 的后续项。
void main() {
  group('AppRadius（圆角刻度）', () {
    test('含直角与全圆，且刻度递增', () {
      expect(AppRadius.none, 0);
      expect(AppRadius.full, greaterThanOrEqualTo(999));
      final scale = [
        AppRadius.none,
        AppRadius.sm,
        AppRadius.md,
        AppRadius.lg,
        AppRadius.xl,
        AppRadius.xxl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('遮罩默认圆角为 lg(12)：桌面 UI 依赖该值', () {
      expect(AppRadius.lg, 12);
    });
  });

  group('AppSpace（间距刻度）', () {
    test('刻度递增且包含紧凑值 2/6', () {
      final scale = [
        AppSpace.xxs,
        AppSpace.xs,
        AppSpace.tiny,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xl,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
      expect(AppSpace.xxs, 2);
      expect(AppSpace.tiny, 6);
    });
  });

  group('AppTopBar（桌面顶部边界）', () {
    test('边界 = 标题栏高度 + 余量', () {
      expect(AppTopBar.boundary, AppTopBar.height + AppTopBar.extra);
    });

    test('标题栏高度 36、边界 42（与 window_frame 的自绘标题栏一致）', () {
      expect(AppTopBar.height, 36);
      expect(AppTopBar.boundary, 42);
    });

    test('boundaryPadding 顶部等于边界值', () {
      expect(AppTopBar.boundaryPadding.top, AppTopBar.boundary);
    });
  });

  group('AppTextScale（字号缩放范围）', () {
    test('clamp 收敛到 [min, max]', () {
      expect(AppTextScale.clamp(0.5), AppTextScale.min);
      expect(AppTextScale.clamp(2.0), AppTextScale.max);
      expect(AppTextScale.clamp(1.2), 1.2);
      expect(AppTextScale.clamp(1.4), 1.4);
    });

    test('默认值落在范围内且上下限符合约定（0.8 / 1.4）', () {
      expect(AppTextScale.defaultValue, 1.0);
      expect(AppTextScale.min, 0.8);
      expect(AppTextScale.max, 1.4);
    });
  });

  group('AppMotion（动效时长）', () {
    test('时长递增且为 Material 3 常用值', () {
      expect(AppMotion.short, const Duration(milliseconds: 200));
      expect(AppMotion.medium, const Duration(milliseconds: 300));
      expect(AppMotion.long, const Duration(milliseconds: 400));
      expect(AppMotion.short < AppMotion.medium, isTrue);
      expect(AppMotion.medium < AppMotion.long, isTrue);
    });
  });

  group('AppOpacity（透明度约定）', () {
    test('取值范围合法且默认色调强度为 0.22', () {
      expect(AppOpacity.tintStrengthDefault, 0.22);
      for (final v in [
        AppOpacity.tintStrengthDefault,
        AppOpacity.solid,
        AppOpacity.disabled,
        AppOpacity.hint,
        AppOpacity.hoverInk,
        AppOpacity.selectedTint,
      ]) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
