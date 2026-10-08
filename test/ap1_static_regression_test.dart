import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AP1 修复的**静态回归测试**（来源 `doc-private/17-fix-list-and-test-needs.md` 的测试需求）。
///
/// 全部是**纯静态扫描**：不启动 Widget、不依赖 appdata → 零风险、跑得快，
/// 目的是把 C5 / C8 / C6-新① 三项修复钉死：任何一处回退都会让本文件变红。
///
/// ⚠️ 两条经验（写这些测试时踩到过）：
/// 1. **注释里的字样也算命中** —— 例如注释里写了"原始实现见 `BackdropFilter`"，
///    直接 `contains` 会误判 → 因此扫描前先 **剥掉注释行**。
/// 2. **正则片段不要在测试里再转义一遍** —— 用朴素子串判断即可，避免 `\\s\*` 这类错。
void main() {
  /// 剥掉整行注释（`//` 开头）与行尾注释，避免注释里的字样造成误判。
  String stripComments(String text) {
    return text
        .split('\n')
        .map((line) {
          final idx = line.indexOf('//');
          return idx >= 0 ? line.substring(0, idx) : line;
        })
        .join('\n');
  }

  group('AP1 静态回归', () {
    test('T-C5：所有 AppTabBar 调用点都传了 Tab(height: AppTopBar.tabHeight)', () {
      // 背景：C5 修复前，其中 4 个页面漏传 `height` → chip 走 `kTabHeight` 默认 46，
      // 而发现/分类页是 36（同类控件跨页不一致 → 审计 AP1-C5）。
      const files = <String>[
        'lib/pages/categories_page.dart', // 分类页（对照基准）
        'lib/pages/explore_page.dart', // 发现页（对照基准）
        'lib/pages/comic_details_page/chapters.dart', // C5 修复点 ①
        'lib/pages/reader/chapters.dart', // C5 修复点 ②
        'lib/pages/favorites/local_favorites_page.dart', // C5 修复点 ③
        'lib/pages/image_favorites_page/image_favorites_page.dart', // C5 修复点 ④
      ];
      final missing = <String>[];
      for (final path in files) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '源文件不存在：$path');
        final text = stripComments(file.readAsStringSync());
        if (!text.contains('Tab(')) {
          missing.add('$path（找不到 Tab( 调用点，页面结构可能已变）');
          continue;
        }
        if (!text.contains('AppTopBar.tabHeight')) {
          missing.add('$path（缺少 height: AppTopBar.tabHeight）');
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            '以下调用点未使用高度令牌（会让该页 chip 变回 46px，见审计 AP1-C5）：\n'
            '${missing.join('\n')}',
      );
    });

    test('T-C8：外观守卫的「裸透明度」规则覆盖四种写法且已纳入基线', () {
      // 背景：C8 修复前，守卫正则只认 `.withOpacity(0.x)` →
      // `.toOpacity` / `.withValues(alpha:)` / `.withAlpha` 全部漏网（实测 45 处）。
      final guard = File('tool/appearance_guard.dart');
      expect(guard.existsSync(), isTrue, reason: '守卫脚本不存在');
      final text = stripComments(guard.readAsStringSync());
      final missing = <String>[
        for (final form in const [
          '.withOpacity',
          '.toOpacity',
          '.withValues',
          '.withAlpha',
        ])
          if (!text.contains(form)) '$form（规则未覆盖）',
      ];
      expect(
        missing,
        isEmpty,
        reason: '「裸透明度」规则未覆盖全部写法（见审计 AP1-C8）：\n${missing.join('\n')}',
      );

      final baseline = File('tool/appearance_baseline.json');
      expect(baseline.existsSync(), isTrue, reason: '基线文件不存在');
      expect(
        baseline.readAsStringSync(),
        contains('裸透明度'),
        reason: '基线缺少「裸透明度」指标 → 该规则不会被棘轮监督（见 AP1-C8）',
      );
    });

    test('T-C6-新①：毛玻璃已按用户要求整体移除', () {
      // 背景：用户 2026-10-09 明确"不喜欢毛玻璃，全部移除都可以" → `BlurEffect` 改直通
      // （提交 `911bba4`）。断言：`effects.dart` 的**代码**里不再出现真实模糊调用。
      final effects = File('lib/components/effects.dart');
      expect(effects.existsSync(), isTrue, reason: 'effects.dart 不存在');
      final text = stripComments(effects.readAsStringSync());
      expect(
        text.contains('BackdropFilter'),
        isFalse,
        reason:
            'BlurEffect 又用上了 BackdropFilter → 与用户"全部移除毛玻璃"的要求冲突'
            '（见 AP1 C6-新① / 提交 911bba4）',
      );
      expect(
        text.contains('ImageFilter.blur'),
        isFalse,
        reason: 'BlurEffect 又用上了 ImageFilter.blur → 同上',
      );
      expect(
        text.contains('return child;'),
        isTrue,
        reason: 'BlurEffect 应保持直通（只返回 child）',
      );
    });
  });
}
