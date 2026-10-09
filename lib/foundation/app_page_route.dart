import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/design_tokens.dart';

const double _kBackGestureWidth = 20.0;
const int _kMaxDroppedSwipePageForwardAnimationTime = 800;
const int _kMaxPageBackAnimationTime = 300;
const double _kMinFlingVelocity = 1.0;

class AppPageRoute<T> extends PageRoute<T> with _AppRouteTransitionMixin {
  /// Construct a MaterialPageRoute whose contents are defined by [builder].
  AppPageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    // ⭐ 修复（2026-10-09 用户 Android 实测 ✓）：**关闭路由过渡快照** ✗→✓。
    // 现象：安卓端"进入下一级页面（设置 / 历史页等）会闪白" ✓，而 Windows 端无此现象 ✓
    //（该优化是 Android 侧行为 ✓）。快照在背景层尚未绘制时取帧 ⇒ 露出白底 ✓。
    // 代价：过渡期间改为实时渲染 ✓（略增开销 ✓），换取不闪白 ✓。
    super.allowSnapshotting = false,
    super.barrierDismissible = false,
    this.enableIOSGesture = true,
    this.preventRebuild = true,
  }) {
    assert(opaque);
  }

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  String? label;

  @override
  toString() => "/$label";

  @override
  Widget buildContent(BuildContext context) {
    var widget = builder(context);
    label = widget.runtimeType.toString();
    return widget;
  }

  @override
  final bool maintainState;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';

  @override
  final bool enableIOSGesture;

  @override
  final bool preventRebuild;
}

mixin _AppRouteTransitionMixin<T> on PageRoute<T> {
  /// Builds the primary contents of the route.
  @protected
  Widget buildContent(BuildContext context);

  @override
  Duration get transitionDuration => AppMotion.medium;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    // Don't perform outgoing animation if the next route is a fullscreen dialog.
    return nextRoute is PageRoute && !nextRoute.fullscreenDialog;
  }

  bool get enableIOSGesture;

  bool get preventRebuild;

  Widget? _child;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget result;

    if (preventRebuild) {
      result = _child ?? (_child = buildContent(context));
    } else {
      result = buildContent(context);
    }

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: result,
    );
  }

  static bool _isPopGestureEnabled<T>(PageRoute<T> route) {
    if (route.isFirst ||
        route.willHandlePopInternally ||
        route.popDisposition == RoutePopDisposition.doNotPop ||
        route.fullscreenDialog ||
        route.animation!.status != AnimationStatus.completed ||
        route.secondaryAnimation!.status != AnimationStatus.dismissed ||
        !route.popGestureEnabled ||
        route.navigator!.userGestureInProgress) {
      return false;
    }

    return true;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    PageTransitionsBuilder builder;
    if (App.isAndroid) {
      builder = PredictiveBackPageTransitionsBuilder();
    } else {
      builder = SlidePageTransitionBuilder();
    }

    return builder.buildTransitions(
      this,
      context,
      animation,
      secondaryAnimation,
      enableIOSGesture && App.isIOS
          ? IOSBackGestureDetector(
              gestureWidth: _kBackGestureWidth,
              enabledCallback: () => _isPopGestureEnabled<T>(this),
              onStartPopGesture: () => _startPopGesture(this),
              child: child,
            )
          : child,
    );
  }

  IOSBackGestureController _startPopGesture(PageRoute<T> route) {
    return IOSBackGestureController(route.controller!, route.navigator!);
  }
}

class IOSBackGestureController {
  final AnimationController controller;

  final NavigatorState navigator;

  IOSBackGestureController(this.controller, this.navigator) {
    navigator.didStartUserGesture();
  }

  void dragEnd(double velocity) {
    const Curve animationCurve = Curves.fastLinearToSlowEaseIn;
    final bool animateForward;

    if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      final droppedPageForwardAnimationTime = min(
        lerpDouble(
          _kMaxDroppedSwipePageForwardAnimationTime,
          0,
          controller.value,
        )!.floor(),
        _kMaxPageBackAnimationTime,
      );
      controller.animateTo(
        1.0,
        duration: Duration(milliseconds: droppedPageForwardAnimationTime),
        curve: animationCurve,
      );
    } else {
      navigator.pop();
      if (controller.isAnimating) {
        final droppedPageBackAnimationTime = lerpDouble(
          0,
          _kMaxDroppedSwipePageForwardAnimationTime,
          controller.value,
        )!.floor();
        controller.animateBack(
          0.0,
          duration: Duration(milliseconds: droppedPageBackAnimationTime),
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }

  void dragUpdate(double delta) {
    controller.value -= delta;
  }
}

class IOSBackGestureDetector extends StatefulWidget {
  const IOSBackGestureDetector({
    required this.enabledCallback,
    required this.child,
    required this.gestureWidth,
    required this.onStartPopGesture,
    super.key,
  });

  final double gestureWidth;
  final bool Function() enabledCallback;
  final IOSBackGestureController Function() onStartPopGesture;
  final Widget child;

  @override
  State<IOSBackGestureDetector> createState() => _IOSBackGestureDetectorState();
}

class _IOSBackGestureDetectorState extends State<IOSBackGestureDetector> {
  IOSBackGestureController? _backGestureController;
  late _BackSwipeRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = _BackSwipeRecognizer(
      debugOwner: this,
      gestureWidth: widget.gestureWidth,
      isPointerInHorizontal: _isPointerInHorizontalScrollable,
      onStart: _handleDragStart,
      onUpdate: _handleDragUpdate,
      onEnd: _handleDragEnd,
      onCancel: _handleDragCancel,
    );
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _BackSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_BackSwipeRecognizer>(
              () => _recognizer,
              (instance) {
                instance.gestureWidth = widget.gestureWidth;
              },
            ),
      },
      child: widget.child,
    );
  }

  bool _isPointerInHorizontalScrollable(Offset globalPosition) {
    final HitTestResult result = HitTestResult();
    final binding = WidgetsBinding.instance;
    binding.hitTestInView(
      result,
      globalPosition,
      binding.platformDispatcher.implicitView!.viewId,
    );

    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderViewport) {
        if (target.axisDirection == AxisDirection.left ||
            target.axisDirection == AxisDirection.right) {
          return true;
        }
      } else if (target is RenderSliver) {
        if (target.constraints.axisDirection == AxisDirection.left ||
            target.constraints.axisDirection == AxisDirection.right) {
          return true;
        }
      } else if (target.runtimeType.toString() ==
          '_RenderSingleChildViewport') {
        try {
          final dynamic renderObject = target;
          if (renderObject.axis == Axis.horizontal) {
            return true;
          }
        } catch (e) {
          // protected
        }
      } else if (target is RenderEditable) {
        return true;
      }
    }
    return false;
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabledCallback()) return;
    if (mounted && _backGestureController == null) {
      _backGestureController = widget.onStartPopGesture();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (mounted && _backGestureController != null) {
      _backGestureController!.dragUpdate(
        _convertToLogical(details.primaryDelta! / context.size!.width),
      );
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (mounted && _backGestureController != null) {
      _backGestureController!.dragEnd(
        _convertToLogical(
          details.velocity.pixelsPerSecond.dx / context.size!.width,
        ),
      );
      _backGestureController = null;
    }
  }

  void _handleDragCancel() {
    if (mounted && _backGestureController != null) {
      _backGestureController?.dragEnd(0.0);
      _backGestureController = null;
    }
  }

  double _convertToLogical(double value) {
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        return -value;
      case TextDirection.ltr:
        return value;
    }
  }
}

class _BackSwipeRecognizer extends OneSequenceGestureRecognizer {
  _BackSwipeRecognizer({
    required this.isPointerInHorizontal,
    required this.gestureWidth,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    super.debugOwner,
  });

  final bool Function(Offset globalPosition) isPointerInHorizontal;
  double gestureWidth;
  final ValueSetter<DragStartDetails> onStart;
  final ValueSetter<DragUpdateDetails> onUpdate;
  final ValueSetter<DragEndDetails> onEnd;
  final VoidCallback onCancel;

  Offset? _startGlobal;
  bool _accepted = false;
  bool _startedInHorizontal = false;
  bool _startedNearLeftEdge = false;

  VelocityTracker? _velocityTracker;

  static const double _minDistance = 5.0;

  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _startGlobal = event.position;
    _accepted = false;

    _startedInHorizontal = isPointerInHorizontal(event.position);
    _startedNearLeftEdge = event.position.dx <= gestureWidth;

    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker?.addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent || event is PointerUpEvent) {
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }

    if (event is PointerMoveEvent) {
      if (_startGlobal == null) return;
      final delta = event.position - _startGlobal!;
      final dx = delta.dx;
      final dy = delta.dy.abs();

      if (!_accepted) {
        if (delta.distance < _minDistance) return;

        final isRight = dx > 0;
        final isHorizontal = dx.abs() > dy * 1.5;
        final bool eligible = _startedNearLeftEdge || (!_startedInHorizontal);

        if (isRight && isHorizontal && eligible) {
          _accepted = true;
          resolve(GestureDisposition.accepted);
          onStart(
            DragStartDetails(
              globalPosition: _startGlobal!,
              localPosition: event.localPosition,
            ),
          );
        } else {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          _startGlobal = null;
          _velocityTracker = null;
        }
      }

      if (_accepted) {
        onUpdate(
          DragUpdateDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
            primaryDelta: event.delta.dx,
            delta: Offset(event.delta.dx, 0),
          ),
        );
      }
    } else if (event is PointerUpEvent) {
      if (_accepted) {
        final Velocity velocity =
            _velocityTracker?.getVelocity() ?? Velocity.zero;

        onEnd(
          DragEndDetails(
            velocity: velocity,
            primaryVelocity: velocity.pixelsPerSecond.dx,
          ),
        );
      }
      _reset();
    } else if (event is PointerCancelEvent) {
      if (_accepted) {
        onCancel();
      }
      _reset();
    }
  }

  void _reset() {
    stopTrackingPointer(0);
    _accepted = false;
    _startGlobal = null;
    _startedInHorizontal = false;
    _startedNearLeftEdge = false;
    _velocityTracker = null;
  }

  @override
  String get debugDescription => 'IOSBackSwipe';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

class SlidePageTransitionBuilder extends PageTransitionsBuilder {
  /// ⭐ AY1（用户要求 ✓，2026-10-09）：**强制走横切分支** ✓ ——
  /// 用户原话："**我想让你在有背景、或者说任何情况下，这四个页面都保持横向切入** ✓，
  /// 且**效果要和设置的横向切入统一，不要搞差分** ✓"。
  /// 因此这里给 builder 加一个开关 ✓：默认 false（= App 全局原样 ✓，有背景时仍用 fade-through ✓）；
  /// 「设置 → 外观」四个子页的路由传 `true` ✓ → **任何情况下都走横切** ✓
  ///（**同一份实现** ✓，只跳过背景分支 ✗ → 不产生第二套转场 ✗）。
  const SlidePageTransitionBuilder({this.forceSlide = false});

  final bool forceSlide;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> primaryAnimation = App.isIOS
        ? animation
        : CurvedAnimation(parent: animation, curve: Curves.ease);
    final Animation<double> secondaryCurve = App.isIOS
        ? secondaryAnimation
        : CurvedAnimation(parent: secondaryAnimation, curve: Curves.ease);

    // ⭐ AX1（用户实测 ✓，2026-10-09）：这里的判据原本用 **`customBackgroundActive`** ✗，
    // 但该值**恒真** ✗ —— 它 = `backgroundFeatureActive || windowOverlayEnabled || secondaryPageFeatureActive` ✓，
    // 而 `secondaryPageFeatureActive` 默认就是 `opaque ≠ off` ⇒ **true** ✓（审计 C1 复核结论 ✓：
    // 这也是"26 处 else 分支不可达"的同一个根因 ✓）→ 于是**即使没有任何背景**也永远走 fade-through ✗，
    // 用户实测："删掉图片背景 + 颜色背景设透明后，这几个页面**还是淡入**"✓，而他要的是
    // "**跟随全局设计（横向切入）**"✓。
    // **正解** ✓：用 **`backgroundFeatureActive`** ✓ —— 它才是"背景图非空 **或** 底色非透明"（= 页面真的会透明 ✓），
    // 与源码上方的注释语义（"自定义背景时页面背景是透明的，横向滑动会让旧页从新页透明区透出来 ✗"）**完全对应** ✓。
    // ⇒ 无背景 → **横向切入** ✓（恢复 App 原本的全局设计 ✓）；有背景 → 保留 fade-through ✓（避免两页叠加 ✗）。
    // ⭐ AY1：`forceSlide` 为 true 时**跳过背景分支** ✓（供「设置 → 外观」四个子页使用 ✓，用户要求任何情况都横切 ✓）。
    // ⭐ AZ1（用户实测 ✓，2026-10-09）：必须把"**页面是否透明**"与"**是否走 fade 分支**"**拆开** ✗→✓ ——
    // 上一版我把 `forceSlide` 直接并进 `customBg` ✗ → 强制横切时 `customBg` 变 false ✓，
    // 于是下面 `Material(color: customBg ? transparent : null)` 取到 **null = 主题表面色（白）** ✗、
    // `elevation` 变成 **6（带阴影）** ✗ → 用户实测："**有背景的情况下，这四个页面内不显示背景，显示一片空白**"✓（截图 ✓）。
    // **正解** ✓：① "是否透明"只看 `backgroundFeatureActive` ✓（决定 Material 透明与 elevation ✓）；
    //            ② "是否走 fade 分支" = `!forceSlide && 透明` ✓（AY1 的强制横切只管**分支选择** ✓）。
    final transparentPages = App.data.settings.backgroundFeatureActive;
    final customBg = !forceSlide && transparentPages;

    Widget content = PhysicalModel(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      clipBehavior: Clip.hardEdge,
      // 透明色 + elevation>0 会把阴影画进形状内部形成整页暗色遮罩，
      // 自定义背景时必须关掉 elevation（窗口层次改由「窗口遮罩」配置卡片容器）。
      elevation: transparentPages ? 0 : 6,
      child: Material(
        color: transparentPages ? Colors.transparent : null,
        child: child,
      ),
    );

    // 自定义背景时页面背景是透明的，原来的「两页同时滑动」会让旧页面从
    // 新页面的透明区域透出来（残影/两页叠加）。
    // 改为 fade through：旧页面在前 30% 淡出消失，新页面再从 35% 起淡入 ——
    // 两页在时间上不重叠，既无残影，也不会闪底色。
    if (customBg) {
      final fadeIn = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 1.0, curve: Curves.easeIn),
      );
      final fadeOut = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
        ),
      );
      return FadeTransition(
        opacity: fadeOut,
        child: FadeTransition(opacity: fadeIn, child: content),
      );
    }

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(primaryAnimation),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.4, 0),
        ).animate(secondaryCurve),
        child: content,
      ),
    );
  }
}
