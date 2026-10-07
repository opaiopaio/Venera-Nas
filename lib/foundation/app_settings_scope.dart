import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/appdata.dart';

/// 「设置变化 → 相关控件重建」的**唯一正确通路**。
///
/// ## 为什么需要它（背景）
/// 本项目大量控件直接读全局设置（`appdata.settings[...]`、`windowOverlayColor()`、
/// `AppBackground.isActive` …），这些读取**不是响应式的**：设置变了控件不会自己重建。
/// 历史做法是在 `App.forceRebuild()` 里**遍历整棵 element 树 `markNeedsBuild()`**，
/// 那会把 `Navigator`/`Overlay` 中**已退场但未销毁**的路由元素也标脏 →
/// 半渲染/残留图层（表现为"内容切成左右两半、滚轮只滚动背景"的鬼影）。
///
/// ⚠️ **不能用"把 `MaterialApp`/`Navigator` 整体重建一次"来替代**：
/// 已入栈的 `Route.buildPage()` 不会重跑、`OverlayEntry` 内容也不靠上层重建刷新，
/// 深层/弹层控件根本不会更新（表面不鬼影 = 没生效）。
///
/// ## 正确用法
/// `InheritedNotifier` 的依赖传播是**沿元素树向下、覆盖所有 overlay 条目**的
/// （弹层/路由内容都是 `Navigator` 的后代），所以本 scope 挂在 **Navigator 之上**
/// （见 `main.dart` 的 `MaterialApp.builder`），任何**声明依赖**它的控件在设置变化时
/// 都会被框架**精准重建**，无论在第几层路由里。
///
/// 需要"设置一变就刷新"的控件，在 `build` 或 `didChangeDependencies` 里调用一次：
/// ```dart
/// AppSettingsScope.of(context); // 建立依赖，返回 Settings（也可直接忽略返回值）
/// ```
/// 高频写入（滑条）只会重建**真正依赖的控件**，不再有"每帧全树遍历"的开销。
class AppSettingsScope extends InheritedNotifier<Settings> {
  // 不能是 `const`：notifier 取的是运行时的全局 `appdata.settings`
  AppSettingsScope({super.key, required super.child})
    : super(notifier: appdata.settings);

  /// 建立对设置的依赖：设置变化时本控件会被框架重建。
  ///
  /// 必须在 `build`/`didChangeDependencies`（而非回调）里调用，才能注册依赖。
  static Settings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(
      scope != null,
      'AppSettingsScope 不在祖先链上：请确认它在 main.dart 的 MaterialApp.builder '
      '里包住了 Navigator（弹层/路由内容都在其下）。',
    );
    return scope!.notifier!;
  }

  /// 不建立依赖、只取值的版本（用于回调里读取，避免误建依赖）。
  static Settings? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppSettingsScope>()?.notifier;
}

/// 依赖设置的**构建器**：设置变化时重新执行 [builder]。
///
/// 用途：那些"外观由**非 widget 的 helper** 算好"的地方 —— 典型是 `toSliver()`：
/// 它在**调用点**就算好了 `Padding`/`Material` 的遮罩色与圆角，这些包装 widget
/// 没有自己的元素去建依赖；所以必须由本构建器在设置变化时**重建包装**。
///
/// 用法：`SliverToBoxAdapter(child: SettingsBuilder(builder: (context) => ...))`
class SettingsBuilder extends StatelessWidget {
  const SettingsBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    AppSettingsScope.of(context); // 建立依赖 → 设置变化时重跑 builder
    return builder(context);
  }
}
