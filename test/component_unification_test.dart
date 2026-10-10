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

  test('T-CU2：多选工具条必须走规范构件 SelectToolbar（第二批）', () {
    // 背景 ✗：这 6 个页面原先各自逐行重写同一组按钮（全选/取消/反选/删除 ✓）
    // ⇒ 已统一到 `lib/components/select_toolbar.dart` ✓。本测试防止回退 ✗。
    const toolbarFiles = <String>[
      'lib/pages/home_page.dart',
      'lib/pages/history_page.dart',
      'lib/pages/local_comics_page.dart',
      'lib/pages/comic_details_page/comic_page.dart',
      'lib/pages/image_favorites_page/image_favorites_page.dart',
      'lib/pages/image_favorites_page/image_favorites_gallery_page.dart',
    ];

    for (final path in toolbarFiles) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('SelectToolbar('),
        isTrue,
        reason: '$path 的多选工具条应使用规范构件 SelectToolbar',
      );
      // tooltip 文案是稳定的"手写指纹" ✓：手写版本必然带它 ✓。
      expect(
        RegExp(r'tooltip:\s*"Invert Selection"').hasMatch(src),
        isFalse,
        reason: '$path 不应再手写多选工具条按钮（应走 SelectToolbar）',
      );
    }

    // 规范实现内部应只剩一处该文案 ✓（保证"唯一实现" ✓）。
    final impl = File('lib/components/select_toolbar.dart').readAsStringSync();
    expect(
      RegExp(r'"Invert Selection"').allMatches(impl).length,
      equals(1),
      reason: 'SelectToolbar 应是多选工具条的唯一实现',
    );
  });
}
