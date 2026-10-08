import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **AX1 静态回归测试**：锁死"转场走横切还是淡入"的**判据**。
///
/// 背景（用户 2026-10-09 实测 ✓）：
/// - 用户把"没有背景"定义为：**删掉图片背景 + 颜色背景设为透明** ✓；
/// - 在这种"无背景"情况下，进 设置→外观 的四个子页**仍然是淡入** ✗，
///   而用户要的是"**跟随全局设计（横向切入）**"✓（横切是设置页的全局设计 ✓）。
///
/// 真因 ✓：`foundation/app_page_route.dart` 的 `SlidePageTransitionBuilder` 里，
/// 判据用的是 **`customBackgroundActive`** ✗ —— 而该值**恒真** ✗
///（`= backgroundFeatureActive || windowOverlayEnabled || secondaryPageFeatureActive`，
///  其中 `secondaryPageFeatureActive` 默认 `opaque ≠ off` ⇒ true ✓；这也是审计 C1 复核的同一根因 ✓）
/// → 于是**没有任何背景时也永远走 fade-through** ✗。
///
/// 修法 ✓：改为 **`backgroundFeatureActive`** ✓（= "背景图非空 **或** 底色非透明" ✓，
/// 与源码中"自定义背景时页面透明、横滑会两页叠加 ✗"的注释语义**完全对应** ✓）。
///
/// 本用例把这一行钉死：一旦有人改回 `customBackgroundActive` ✗ 或删掉该判据 ✗，立即变红 ✓。
void main() {
  String stripComments(String text) => text
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');

  test('AX1：转场判据必须是 backgroundFeatureActive（不得回退 customBackgroundActive）', () {
    final file = File('lib/foundation/app_page_route.dart');
    expect(file.existsSync(), isTrue, reason: 'app_page_route.dart 不存在');
    final text = stripComments(file.readAsStringSync());

    expect(
      text.contains('App.data.settings.backgroundFeatureActive'),
      isTrue,
      reason:
          '转场判据不是 backgroundFeatureActive → 无背景时也会走淡入（用户实测反馈过：'
          '"删掉图片背景+底色透明后仍然淡入"）',
    );
    // ⭐ AY1（用户要求 ✓）：四个外观子页要"任何情况都横切" → builder 需有 forceSlide 开关 ✓
    //（默认 false = App 全局原样 ✓；子页传 true ✓），且「设置 → 外观」必须用上它 ✓。
    expect(
      text.contains('forceSlide'),
      isTrue,
      reason: '缺少 forceSlide 开关 → 有背景时无法为指定页面强制横切（用户 AY1 要求）',
    );
    final appearance = stripComments(
      File('lib/pages/settings/appearance.dart').readAsStringSync(),
    );
    expect(
      appearance.contains('forceSlide: true'),
      isTrue,
      reason: '外观四个子页未启用 forceSlide → 有背景时仍会淡入（不是"任何情况都横切"）',
    );
    expect(
      text.contains('customBackgroundActive'),
      isFalse,
      reason:
          '又用回了 customBackgroundActive（它恒真：secondaryPageFeatureActive 默认 true）'
          '→ 会导致"无背景时也淡入"，即 AX1 复发；有背景时横滑还会两页叠加',
    );
    // 横切分支必须仍在（否则"无背景时横向切入"就没了）
    expect(
      text.contains('Offset(1, 0)'),
      isTrue,
      reason: '横向切入分支缺失（无背景时应走 SlideTransition 横切）',
    );

    // ⭐ 复查补强（2026-10-09 ✓）：**守护 AZ1 的拆分** ✗→✓ ——
    // AZ1 的回归是"把 `forceSlide` 并进 `customBg` ⇒ 强制横切时 Material 变不透明白 + elevation 6
    // ⇒ 有背景时四个子页**一片空白**"✓（用户截图实测 ✓）。当时只断言了"存在 forceSlide 开关"✗，
    // 若有人把 `elevation:`/`color:` 改回 `customBg`，原断言**仍会全绿** ✗ = 静默复发 ✓。
    expect(
      text.contains(
        'final transparentPages = App.data.settings.backgroundFeatureActive;',
      ),
      isTrue,
      reason: '缺少 transparentPages（AZ1 的拆分变量）→ 白板回归可静默复活',
    );
    expect(
      text.contains('elevation: transparentPages ? 0 : 6'),
      isTrue,
      reason: 'elevation 未取 transparentPages → 强制横切时会变成 6（带阴影），AZ1 复发',
    );
    expect(
      text.contains('color: transparentPages ? Colors.transparent : null'),
      isTrue,
      reason: 'Material.color 未取 transparentPages → 强制横切时变成不透明主题色（白板），AZ1 复发',
    );
  });
}
