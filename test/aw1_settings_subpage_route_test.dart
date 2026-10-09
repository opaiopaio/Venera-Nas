import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **AW1 静态回归测试**：把「设置 → 外观」四个子页的重构约束钉死。
///
/// 用户 2026-10-09 的要求原话：
/// 「**重构一下这几个页面，就用设置页原本的设计（横向切入）就好** ✓，
///  **但是注意之前的刷新问题**（点击发现、阅读中等设置右侧页面不更新、被第二层级覆盖）」✓。
///
/// 我在调查后确认（有代码证据）：
/// - 「设置页原本的设计」= `AppPageRoute` 的转场 `SlidePageTransitionBuilder`
///   （`foundation/context.dart:20` 的 `context.to` 用的就是 `AppPageRoute`；
///   设置页自己由 `pages/main_page.dart:102` 的 `to(() => const SettingsPage())` 打开）。
/// - 该转场**有两种模式**（`foundation/app_page_route.dart:483-548`）：
///   无自定义背景 → **横向切入**；**有自定义背景 → 刻意用 fade-through（浮现）**
///   （源码注释：横向滑动会让旧页从新页透明区透出来，形成"残影/两页叠加"）。
/// - 因此这四个子页**复用同一个 `SlidePageTransitionBuilder`** 即为"与设置页一致"。
///
/// ⚠️ **2026-10-09 变更（用户指示 ✓）**：四个外观子页已改为**弹窗形态**
/// （入口 `showPopUpWidget(context, …)` + `PopUpWidgetScaffold(popupStyle: true)`）✓ ——
/// 用户原话「**同化成探索页面那种形式，省的纠结横切和动画 bug**」✗⇒✓。
/// 因此 ③ 的判据已从"必须推在右栏内层 Navigator"（AO1 时期 ✓）改为"必须是弹窗形态" ✓；
/// `SettingsSubPageRoute`（AW1/BA1/AY1/AV1 的成果 ✓）**保留但已不再被这四个入口使用** ✗（死代码，留作回溯 ✓）。
///
/// 本文件锁死三条：① 转场复用 App 自己那一份；② 不得再改 `opaque => false`
/// （曾造成两层页面重合，提交 `f689cee` 回退过）；③ 必须仍推在**右栏内层 Navigator**
/// 且内层 Navigator 仍带 `ValueKey(currentPage)`（AO1 的"点左侧栏立即刷新"就靠这两条）。
void main() {
  String stripComments(String text) => text
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');

  group('AW1 设置外观子页路由', () {
    test('① 转场复用 App 自己的 SlidePageTransitionBuilder', () {
      final file = File('lib/pages/settings/appearance.dart');
      expect(file.existsSync(), isTrue);
      final text = stripComments(file.readAsStringSync());
      expect(
        text.contains('SlidePageTransitionBuilder'),
        isTrue,
        reason: '外观子页未复用 App 自己的转场实现 → 会与"设置页原本的设计"不一致（AW1）',
      );
      expect(
        text.contains('buildTransitions'),
        isTrue,
        reason: '缺少 buildTransitions 覆写 → 又会退回主题默认转场（曾导致白闪）',
      );
    });

    test('② 不得再改 opaque => false（防两层页面重合）', () {
      final text = stripComments(
        File('lib/pages/settings/appearance.dart').readAsStringSync(),
      );
      expect(
        text.contains('opaque => false'),
        isFalse,
        reason:
            'opaque => false 会让下层路由继续绘制 → 透明子页导致"两层设置页重合"'
            '（用户实测反馈过，见提交 f689cee 的回退）',
      );
    });

    test('③ 仍在右栏内层 Navigator 上 push，且内层 Navigator 带 ValueKey(currentPage)', () {
      final appearance = stripComments(
        File('lib/pages/settings/appearance.dart').readAsStringSync(),
      );
      expect(
        appearance.contains(
              'showPopUpWidget(context, const AppearanceBackgroundPage())',
            ) &&
            appearance.contains(
              'showPopUpWidget(context, const AppearanceWindowPage())',
            ) &&
            appearance.contains(
              'showPopUpWidget(context, const AppearanceSecondaryPage())',
            ) &&
            appearance.contains(
              'showPopUpWidget(context, const AppearanceTextPage())',
            ),
        isTrue,
        reason:
            '四个外观子页必须统一为**弹窗形态**（showPopUpWidget + PopUpWidgetScaffold(popupStyle: true)）'
            '—— 用户 2026-10-09 明确要求「同化成探索页面那种形式，省的纠结横切和动画 bug」；'
            '此决定覆盖 AW1 早期"推在右栏内层 Navigator"的要求（AO1：左侧栏点击不被 barrier 吃掉）',
      );
      expect(
        appearance.contains('context.to('),
        isFalse,
        reason:
            '不得再用 context.to(...)（那是根 Navigator 的全屏弹层）'
            '→ 会重现 AO1："点发现/阅读中右侧不刷新、被第二层级覆盖"',
      );

      final settingsPage = stripComments(
        File('lib/pages/settings/settings_page.dart').readAsStringSync(),
      );
      expect(
        settingsPage.contains('ValueKey(currentPage)'),
        isTrue,
        reason:
            '内层 Navigator 必须以 currentPage 为 key（否则 onGenerateRoute 只对新路由生效 '
            '→ 切换设置项时右栏不刷新，AO1 回归）',
      );
    });
  });
}
