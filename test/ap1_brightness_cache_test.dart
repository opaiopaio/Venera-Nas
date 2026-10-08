import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/window_overlay.dart';

/// **T-B1-1 / T-B1-2**：B1（亮色下四项遮罩变近黑灰）的**行为回归测试**。
///
/// 为什么单独一个文件、为什么值得写：
/// - 原 bug：`getTheme()` 对 `theme`(light) 与 `darkTheme`(dark) **各写一次**同一个全局缓存
///   `systemContainerColorCache` → **后求值的暗色恒覆盖亮色** → 亮色界面的窗口/胶囊/图标/标签
///   四项 `system` 遮罩全部拿到近黑灰（用户原话"黑不溜秋"）。
/// - 它以前测不到：`getTheme` 是 App State 的**实例方法**，单测调不到；
///   而既有 `appearance_behavior_test` 的 `setUp` 会把 follow-theme 开关强制改 false
///   并**手工赋缓存**，于是**永远走不到真实 getTheme 路径**。
/// - 现在该判定已抽成 foundation 层函数 `applySystemContainerColorFor(...)`
///   （见 `911bba4` 之后的 B1 抽函数提交），所以这条路径**可以被直接覆盖**了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lightHigh = Color(0xFFE5E9EA); // 亮色中性容器色（示意值）
  const darkHigh = Color(0xFF262B2C); // 暗色中性容器色（示意值）

  /// 模拟 `MaterialApp` 的求值顺序：**先** theme(light)、**后** darkTheme(dark)。
  void simulateMaterialAppThemeEvaluation() {
    applySystemContainerColorFor(
      brightness: Brightness.light,
      systemContainerHigh: lightHigh,
    );
    applySystemContainerColorFor(
      brightness: Brightness.dark,
      systemContainerHigh: darkHigh,
    );
  }

  tearDown(() {
    // 不留副作用：恢复成默认值，避免影响同文件后续用例
    appdata.settings['theme_mode'] = 'system';
    systemContainerColorCache = null;
  });

  test('T-B1-1：theme_mode=light 时，暗色那次 getTheme 不得覆盖亮色缓存', () {
    appdata.settings['theme_mode'] = 'light';
    systemContainerColorCache = null;

    simulateMaterialAppThemeEvaluation();

    expect(
      systemContainerColorCache,
      lightHigh,
      reason: '亮色模式下缓存被暗色覆盖了 —— 这正是 B1 的原始 bug（能效仿出"黑不溜秋"）。',
    );
  });

  test('T-B1-1：theme_mode=dark 时，写入的是暗色缓存', () {
    appdata.settings['theme_mode'] = 'dark';
    systemContainerColorCache = null;

    simulateMaterialAppThemeEvaluation();

    expect(systemContainerColorCache, darkHigh);
  });

  test('T-B1-2：切换生效亮度后缓存会随之变化（值缓存键随之失效）', () {
    // 先亮色
    appdata.settings['theme_mode'] = 'light';
    systemContainerColorCache = null;
    simulateMaterialAppThemeEvaluation();
    expect(systemContainerColorCache, lightHigh);

    // 用户切到深色（模拟平台/设置变化后 MaterialApp 重建）
    appdata.settings['theme_mode'] = 'dark';
    simulateMaterialAppThemeEvaluation();

    expect(
      systemContainerColorCache,
      darkHigh,
      reason:
          '切到深色后系统容器色缓存没有更新 → windowOverlayColor() 会拿旧值（T-B1-2）。'
          '注意 windowOverlayColor() 的缓存键里含 systemContainerColorCache，'
          '所以只要这里更新了，它就会跟着失效重算。',
    );

    // 回到亮色同样要能切回来（防止"只单向生效"）
    appdata.settings['theme_mode'] = 'light';
    simulateMaterialAppThemeEvaluation();
    expect(systemContainerColorCache, lightHigh);
  });

  test('T-B1-1：theme_mode=system 时按平台亮度决定写入哪一份', () {
    appdata.settings['theme_mode'] = 'system';
    systemContainerColorCache = null;
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;

    simulateMaterialAppThemeEvaluation();

    expect(
      systemContainerColorCache,
      platformDark ? darkHigh : lightHigh,
      reason: 'system 模式应跟随平台亮度（测试环境下通常为 light）',
    );
  });
}
