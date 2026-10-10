import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⭐ 外观构件统一守卫 · 第一批（2026-10-10 ✓）
///
/// 「评论 / 点赞」的描边胶囊已收编为**唯一实现** `CommentActionChip` ✓
///（构件内部走规范构件 `Button.outlined` ✓，见 Batch E 2026-10-10 ✓）。
/// 本测试防止它们**回退**成手搓 `Container(0.6 描边 + AppRadius.xl) + InkWell` ✗，
/// 也防止两个页面再次各自直接构造 `Button.outlined` ✗。
///
/// 说明 ✓：本项目已有先例（`ap1_static_regression_test.dart` 用同类静态守卫 ✓）。
void main() {
  const targets = <String>[
    'lib/pages/comic_details_page/comments_page.dart',
    'lib/pages/reader/chapter_comments.dart',
  ];

  test('T-CU1：评论/点赞描边胶囊必须走唯一实现 CommentActionChip', () {
    for (final path in targets) {
      final src = File(path).readAsStringSync();

      // 1) 必须走唯一实现（每个文件 2 处：回复 + 点赞）
      final uses = RegExp(r'CommentActionChip\(').allMatches(src).length;
      expect(
        uses >= 2,
        isTrue,
        reason: '$path 应使用唯一实现 CommentActionChip（期望 ≥2 处，实际 $uses）',
      );

      // 2) 不得在页面里直接构造 Button.outlined（唯一实现在构件内）
      final direct = RegExp(r'Button\.outlined\(').allMatches(src).length;
      expect(
        direct,
        equals(0),
        reason:
            '$path 不应再直接构造 Button.outlined（应走 CommentActionChip，实际 $direct 处）',
      );

      // 3) 不得再出现"手搓描边胶囊"的旧结构特征
      final legacy = RegExp(
        r'borderRadius: BorderRadius\.circular\(AppRadius\.xl\),\s*\n\s*onTap:',
      ).allMatches(src).length;
      expect(
        legacy,
        equals(0),
        reason: '$path 不应再有手搓描边胶囊（Container + InkWell + 0.6 描边，实际 $legacy 处）',
      );
    }

    // 唯一实现内部必须恰好一处 `Button.outlined` ✓（保证"唯一实现" ✓）。
    final impl = File(
      'lib/components/comment_action_chip.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'Button\.outlined\(').allMatches(impl).length,
      equals(1),
      reason: 'CommentActionChip 应是评论/点赞描边胶囊的唯一实现',
    );
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

  test('T-CU3：紧凑图标按钮必须走规范构件 CompactIconButton（第四批）', () {
    // 背景 ✗：`IconButton` 默认 48×48 会把定高行撑高 ⇒ 内容贴底 ✗（用户实测 ✓）；
    // 于是两处各写了一遍同一个"魔法组合"（padding zero + 32×32 ✓）
    // ⇒ 已统一到 `lib/components/compact_icon_button.dart` ✓。本测试防止回退 ✗。
    const compactFiles = <String>[
      'lib/pages/settings/setting_components.dart',
      'lib/pages/image_favorites_page/image_favorites_item.dart',
    ];

    for (final path in compactFiles) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('CompactIconButton('),
        isTrue,
        reason: '$path 的紧凑图标按钮应使用规范构件 CompactIconButton',
      );
      // "魔法组合"的稳定指纹 ✓：手写版本必然同时带这两行 ✓。
      final magic = RegExp(
        r'padding:\s*EdgeInsets\.zero,\s*\n\s*constraints:\s*const BoxConstraints\(\s*minWidth:\s*32,\s*minHeight:\s*32\)',
      );
      expect(
        magic.hasMatch(src),
        isFalse,
        reason: '$path 不应再手写紧凑化魔法组合（应走 CompactIconButton）',
      );
    }

    // 规范实现内部必须恰好带上那两行 ✓（保证"唯一实现" ✓）。
    final impl2 = File(
      'lib/components/compact_icon_button.dart',
    ).readAsStringSync();
    expect(
      impl2.contains('padding: EdgeInsets.zero') &&
          impl2.contains('minWidth: 32, minHeight: 32'),
      isTrue,
      reason: 'CompactIconButton 应保留原来的紧凑化参数（保证观感不变）',
    );
  });
}
