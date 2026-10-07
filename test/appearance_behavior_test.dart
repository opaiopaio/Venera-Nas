import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/app_theme.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/text_style_settings.dart';
import 'package:venera_nas/foundation/window_overlay.dart';

/// 外观体系**行为测试**（P4，借上游 `app_test_harness` 的思路但更轻量）。
///
/// `appdata.settings` 在构造时即填充默认值，因此无需 path_provider 脚手架；
/// 通过 setUp/tearDown 复位被改动的键，保证测试之间互不污染、且**不落盘**。
void main() {
  // 会改动的设置键（测试前后复位）
  const touched = <String>[
    'windowOverlayCorner',
    'windowOverlayColor',
    'windowOverlayOpacity',
    'backgroundImage',
    'backgroundColor',
    'globalTextColor',
    'globalFontFamily',
    'globalFontScale',
    'textShadowEnabled',
    'textGlowEnabled',
    'secondaryPageMode',
    'secondaryPageTint',
    'secondaryPageTintStrength',
  ];
  final original = <String, dynamic>{};

  setUp(() {
    for (final k in touched) {
      original[k] = appdata.settings[k];
    }
    // 固定"跟随系统"色，便于断言
    systemContainerColorCache = const Color(0xFFEADDFF);
  });

  tearDown(() {
    for (final k in touched) {
      appdata.settings[k] = original[k];
    }
    systemContainerColorCache = null;
  });

  group('② 遮罩形状：圆角 / 直角', () {
    test('直角设置 → 半径 0（且圆角设置 → 12）', () {
      appdata.settings['windowOverlayCorner'] = 'square';
      expect(windowOverlayRadius(), 0);
      expect(windowOverlayBorderRadius(), BorderRadius.zero);

      appdata.settings['windowOverlayCorner'] = 'rounded';
      expect(windowOverlayRadius(), 12);
      expect(windowOverlayBorderRadius(), BorderRadius.circular(12));
    });
  });

  group('② 遮罩色 × 不透明度合成', () {
    test('transparent → 全透明（不填充）', () {
      appdata.settings['windowOverlayColor'] = 'transparent';
      expect(windowOverlayColor(), Colors.transparent);
    });

    test('system → 取系统容器色缓存，并乘以不透明度', () {
      appdata.settings['windowOverlayColor'] = 'system';
      appdata.settings['windowOverlayOpacity'] = 1.0;
      expect(windowOverlayColor().toARGB32(), 0xFFEADDFF);

      appdata.settings['windowOverlayOpacity'] = 0.5;
      expect(windowOverlayColor().a, closeTo(0.5, 0.01));
    });

    test('自定义色 → 精确取该色 × 不透明度', () {
      appdata.settings['windowOverlayColor'] = '#336699';
      appdata.settings['windowOverlayOpacity'] = 1.0;
      expect(windowOverlayColor().toARGB32(), 0xFF336699);

      appdata.settings['windowOverlayOpacity'] = 0.35;
      final c = windowOverlayColor();
      expect((c.r * 255).round(), 0x33);
      expect((c.g * 255).round(), 0x66);
      expect((c.b * 255).round(), 0x99);
      expect(c.a, closeTo(0.35, 0.01));
    });

    test('不透明度 0 → 全透明', () {
      appdata.settings['windowOverlayColor'] = '#336699';
      appdata.settings['windowOverlayOpacity'] = 0.0;
      expect(windowOverlayColor(), Colors.transparent);
    });
  });

  group('④ 全局文字：未配置时零干预', () {
    test('默认（跟随系统、无阴影发光）→ globalTextStyle() 为 null', () {
      appdata.settings['globalTextColor'] = 'system';
      appdata.settings['globalFontFamily'] = '';
      appdata.settings['textShadowEnabled'] = false;
      appdata.settings['textGlowEnabled'] = false;
      expect(globalTextStyle(), isNull);
      expect(globalTextColor(), isNull);
      expect(globalFontFamily(), isNull);
    });

    test('设置颜色/字体后 → 返回对应样式', () {
      appdata.settings['globalTextColor'] = '#FF00FF';
      appdata.settings['globalFontFamily'] = 'monospace';
      final style = globalTextStyle();
      expect(style, isNotNull);
      expect(style!.color?.toARGB32(), 0xFFFF00FF);
      expect(style.fontFamily, 'monospace');
    });

    test('开启阴影/发光 → shadows 非空', () {
      appdata.settings['globalTextColor'] = 'system';
      appdata.settings['textShadowEnabled'] = true;
      expect(globalTextStyle()?.shadows, isNotEmpty);
      appdata.settings['textShadowEnabled'] = false;
      appdata.settings['textGlowEnabled'] = true;
      expect(globalTextStyle()?.shadows, isNotEmpty);
    });

    test('字号缩放收敛到 [0.8, 1.4]', () {
      appdata.settings['globalFontScale'] = 3.0;
      expect(globalFontScale(), 1.4);
      appdata.settings['globalFontScale'] = 0.1;
      expect(globalFontScale(), 0.8);
    });
  });

  group('① 背景未启用时零回归', () {
    test('无图且底色透明 → customBackgroundAware 原样返回', () {
      appdata.settings['backgroundImage'] = '';
      appdata.settings['backgroundColor'] = 'transparent';
      expect(customBackgroundAware(Colors.red), Colors.red);
      expect(customBackgroundAware(null), isNull);
    });

    test('设置了底色或背景图 → 返回透明（让背景透出）', () {
      appdata.settings['backgroundImage'] = '';
      appdata.settings['backgroundColor'] = '#112233';
      expect(customBackgroundAware(Colors.red), Colors.transparent);

      appdata.settings['backgroundColor'] = 'transparent';
      appdata.settings['backgroundImage'] = 'background.jpg';
      expect(customBackgroundAware(Colors.red), Colors.transparent);
    });
  });

  group('⑤ 按需遮罩 maskIfNeeded（设置行遮罩入口）', () {
    const child = SizedBox.shrink();

    test('masked = false → 原样返回同一个 widget（零回归）', () {
      expect(identical(maskIfNeeded(false, child), child), isTrue);
    });

    test('masked = true → 包一层 WindowOverlayBox，child 原样透传', () {
      final w = maskIfNeeded(true, child);
      expect(w, isA<WindowOverlayBox>());
      expect(identical((w as WindowOverlayBox).child, child), isTrue);
    });

    test('masked = true → margin 透传给 WindowOverlayBox', () {
      const margin = EdgeInsets.only(top: AppSpace.xs);
      final w = maskIfNeeded(true, child, margin: margin) as WindowOverlayBox;
      expect(w.margin, margin);
    });
  });
}
