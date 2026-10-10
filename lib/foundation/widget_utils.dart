import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/window_overlay.dart';
import 'package:venera_nas/foundation/app_theme.dart';

extension WidgetExtension on Widget {
  Widget padding(EdgeInsetsGeometry padding) {
    return Padding(padding: padding, child: this);
  }

  Widget paddingLeft(double padding) {
    return Padding(
      padding: EdgeInsets.only(left: padding),
      child: this,
    );
  }

  Widget paddingRight(double padding) {
    return Padding(
      padding: EdgeInsets.only(right: padding),
      child: this,
    );
  }

  Widget paddingTop(double padding) {
    return Padding(
      padding: EdgeInsets.only(top: padding),
      child: this,
    );
  }

  Widget paddingBottom(double padding) {
    return Padding(
      padding: EdgeInsets.only(bottom: padding),
      child: this,
    );
  }

  Widget paddingVertical(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: this,
    );
  }

  Widget paddingHorizontal(double padding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: this,
    );
  }

  Widget paddingAll(double padding) {
    return Padding(padding: EdgeInsets.all(padding), child: this);
  }

  Widget toCenter() {
    return Center(child: this);
  }

  Widget toAlign(AlignmentGeometry alignment) {
    return Align(alignment: alignment, child: this);
  }

  Widget sliverPadding(EdgeInsetsGeometry padding) {
    return SliverPadding(padding: padding, sliver: this);
  }

  Widget sliverPaddingHorizontal(double padding) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      sliver: this,
    );
  }

  Widget fixWidth(double width) {
    return SizedBox(width: width, child: this);
  }

  Widget fixHeight(double height) {
    return SizedBox(height: height, child: this);
  }

  Widget toSliver() {
    // 配置了「窗口/按钮背景」时，把设置项做成和侧栏项目一致的圆角方框样式
    // （默认透明/未配置时保持原样，零回归）。
    //
    // 遮罩色/圆角是在**这里**算好并塞进 `Padding`/`Material` 的，这些包装 widget
    // 自己没有元素能建依赖 → 必须包一层 [SettingsBuilder]，设置变化时重跑 builder，
    // 遮罩色/圆角才会刷新（否则改「遮罩色/不透明度/圆角」这些设置行不会跟着变）。
    return SliverToBoxAdapter(
      child: SettingsBuilder(
        builder: (context) {
          if (!appdata.settings.hasWindowOverlay) return this;
          // 圆角统一走唯一入口（直角 → 0 / 圆角 → lg）
          final radius =
              windowOverlayBorderRadius() ??
              BorderRadius.circular(AppRadius.lg);
          // 用 Material + 圆角裁切，保证 InkWell 的水波纹/悬停高亮也跟随圆角
          // （普通 Container 裁不到 InkWell 画在 Material 上的墨水层）。
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: AppSpace.xs,
            ),
            child: Material(
              color: windowOverlayColor(),
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: this,
            ),
          );
        },
      ),
    );
  }
}

/// create default text style
TextStyle get ts => const TextStyle();

extension StyledText on TextStyle {
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);

  TextStyle get light => copyWith(fontWeight: FontWeight.w300);

  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);

  TextStyle get underline => copyWith(decoration: TextDecoration.underline);

  TextStyle get lineThrough => copyWith(decoration: TextDecoration.lineThrough);

  TextStyle get overline => copyWith(decoration: TextDecoration.overline);

  TextStyle get s10 => copyWith(fontSize: 10);

  TextStyle get s12 => copyWith(fontSize: 12);

  TextStyle get s14 => copyWith(fontSize: 14);

  TextStyle get s16 => copyWith(fontSize: 16);

  TextStyle get s18 => copyWith(fontSize: 18);

  TextStyle get s20 => copyWith(fontSize: 20);

  TextStyle withColor(Color? color) => copyWith(color: color);
}

extension ColorExt on Color {
  Color toOpacity(double opacity) {
    return withValues(alpha: opacity);
  }
}
