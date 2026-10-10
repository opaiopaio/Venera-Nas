import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⭐ 外观构件统一守卫 · 第一批（2026-10-10 ✓）
///
/// 「评论 / 点赞」的描边胶囊已收编为规范构件 `Button.outlined` ✓。
/// 本测试防止它们**回退**成手搓 `Container(0.6 描边 + AppRadius.xl) + InkWell` ✗。
///
/// 说明 ✓：本项目已有先例（`ap1_static_regression_test.dart` 用同类静态守卫 ✓）。
void main() {
  const targets = <String>[
    'lib/pages/comic_details_page/comments_page.dart',
    'lib/pages/reader/chapter_comments.dart',
  ];

  test('T-CU1：评论/点赞描边胶囊必须走规范构件 Button.outlined', () {
    for (final path in targets) {
      final src = File(path).readAsStringSync();

      // 1) 必须有规范构件（每个文件 2 处：回复 + 点赞）
      final uses = RegExp(r'Button\.outlined\(').allMatches(src).length;
      expect(
        uses >= 2,
        isTrue,
        reason: '$path 应使用规范构件 Button.outlined（期望 ≥2 处，实际 $uses）',
      );

      // 2) 不得再出现"手搓描边胶囊"的旧结构特征
      final legacy = RegExp(
        r'borderRadius: BorderRadius\.circular\(AppRadius\.xl\),\s*\n\s*onTap:',
      ).allMatches(src).length;
      expect(
        legacy,
        equals(0),
        reason: '$path 不应再有手搓描边胶囊（Container + InkWell + 0.6 描边，实际 $legacy 处）',
      );
    }
  });
}
