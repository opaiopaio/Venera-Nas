import 'package:flutter/material.dart';

/// 外观令牌（Design Tokens）——**唯一合法取值来源**。
///
/// 背景 / 遮罩 / 文字 / 形状 / 动效 的所有常量都在这里定义，
/// 业务代码不要写字面量（如 `BorderRadius.circular(12)`、`Duration(milliseconds: 200)`、
/// `withOpacity(0.35)`），一律引用本文件或 `app_theme.dart` 中的令牌。
///
/// 命名与刻度参考 Material 3（借鉴上游 `v1.16.0` 的 `AppMotion`/`AppRadius` 做法）。
/// 圆角/间距见 `app_theme.dart` 的 `AppRadius` / `AppSpace`。

/// 透明度约定（遮罩/色调/状态层）。
abstract final class AppOpacity {
  /// 二级页面「加深/变浅」默认强度。
  static const double tintStrengthDefault = 0.22;

  /// 遮罩/背景图默认不透明度（1.0 = 不透明）。
  static const double solid = 1.0;

  /// 禁用态。
  static const double disabled = 0.38;

  /// 次要提示文字。
  static const double hint = 0.6;

  /// 悬浮/按压墨水强度（状态层）。
  static const double hoverInk = 0.08;

  /// 侧栏项选中底色强度。
  static const double selectedTint = 0.36;
}

/// 动效令牌（Material 3 motion：按组件大小取时长 + emphasized 缓动族）。
///
/// 取自上游 `v1.16.0` 的 `AppMotion` 约定，用于统一动画手感。
abstract final class AppMotion {
  /// 小元件（chip / button / 标签）：200ms。
  static const Duration short = Duration(milliseconds: 200);

  /// 中等元件（侧栏项 / 卡片 / 弹层）：300ms。
  static const Duration medium = Duration(milliseconds: 300);

  /// 大元件（页面转场 / 抽屉）：400ms。
  static const Duration long = Duration(milliseconds: 400);

  /// 强调缓动（进入）：Material 3 emphasized decelerate。
  static const Curve emphasizedIn = Cubic(0.05, 0.7, 0.1, 1.0);

  /// 强调缓动（退出）：Material 3 emphasized accelerate。
  static const Curve emphasizedOut = Cubic(0.3, 0.0, 0.8, 0.15);

  /// 常规缓动（沿用 Flutter 默认曲线语义）。
  static const Curve standard = Curves.easeInOut;
}

/// 全局字号缩放范围（设置页滑块与 TextScaler 上限都取自这里）。
abstract final class AppTextScale {
  static const double min = 0.8;
  static const double max = 1.4;
  static const double defaultValue = 1.0;

  /// 滑块步进。
  static const double step = 0.05;

  /// 把任意值收敛到合法范围。
  static double clamp(double value) => value.clamp(min, max);
}

/// 桌面自绘窗口标题栏相关的顶部边界令牌。
///
/// 窗口内容是 `Positioned.fill` 铺满整窗，页面靠这道边界让位；
/// **不要**依赖 `MediaQuery.padding.top`（实测桌面端 ≈ 0，不可靠）。
abstract final class AppTopBar {
  /// 标题栏高度（程序名 + 窗口按钮所在区域）。
  static const double height = 36;

  /// 额外余量：让首行内容不贴标题栏。
  static const double extra = 6;

  /// 页面内容顶部让位高度（= height + extra）。
  static const double boundary = height + extra;

  /// 供 `MediaQuery.padding.top` 之外的地方直接取用。
  static EdgeInsets get boundaryPadding =>
      const EdgeInsets.only(top: boundary);
}
