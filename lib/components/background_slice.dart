part of 'components.dart';

/// 与**整窗背景层逐像素对齐**的背景切片：**只画不布局**。
///
/// 用途：需要"某块区域显示全窗背景对应部分"的地方 ——
/// 页面顶栏（`components/appbar.dart` 的 `_HeaderSurface`）与
/// 二级页面表面（`components/pop_up_widget.dart` 的 `SecondaryPageSurface`）。
///
/// 原理：把**整窗矩形**（`(-自身在窗口中的位置, 窗口尺寸)`）交给 `paintImage` 绘制，
/// 由调用方用 `ClipRect` / `ClipRRect` 裁成自己的形状 → 得到"该区域作为窗口一扇窗"
/// 的效果（而不是把图片 fit 进自身盒子 = 缩略图 ✗）。
///
/// ⚠️ **历史严重 bug**：同样效果曾用"整窗尺寸的**布局子项** + `OverflowBox`/`Transform`
/// 实现 —— 即使不参与布局，也会在**绘制/合成**层把页面画成
/// "左右两半 + 中间一条能上下滚动的背景带"。
/// **只能画，不能布局**：本组件存在的唯一理由。
///
/// 依赖 `AppSettingsScope`（设置变化即时重建）；位置用 post-frame
/// `localToGlobal` 测量（首帧未知则先画底色，下一帧补上）。
class BackgroundSlice extends StatefulWidget {
  const BackgroundSlice({super.key});

  @override
  State<BackgroundSlice> createState() => _BackgroundSliceState();
}

// ⭐ 修复（2026-10-09 用户实测 ✓）：**切片解码结果的模块级缓存** ✓。
// 起因：`_image` 是**实例字段** ⇒ 每个新 `BackgroundSlice`（顶栏 appbar.dart:136、二级表面
// pop_up_widget.dart:298 —— **每次切页都会新建**）的**第一帧拿不到解码结果** ⇒ 这一帧什么都不画 ⇒
// 露出它下面的底（浅色主题 = colorScheme.surface 白）= 观感"切页时背景重载 / 白一块"。
// 做法：解码完成后把 ui.Image 存到模块级（FileImage 本身已走 Flutter ImageCache，这里只是免掉那一两帧空窗）；
// 换图/清图靠**路径比较**失效（换图处文件名本就每次唯一，见 pages/settings/appearance.dart:388）。
ui.Image? _sliceCachedImage;
String? _sliceCachedPath;

class _BackgroundSliceState extends State<BackgroundSlice> {
  /// 本组件左上角在窗口坐标里的位置。
  Offset? _offsetInWindow;

  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _path;

  // ⭐ 修复（2026-10-09 用户 Android 实测 ✓）：**路由过渡期间逐帧重建** ✓。
  // 现象：偏移 `_offsetInWindow` 是**帧后**测量的 ✗ ⇒ 切页/侧栏滑动时切片**晚一帧** ⇒ 观感"割裂"、
  // "完全展开后背景才推过去填满" ✓。挂上当前路由的 animation ⇒ 过渡期间每帧重建 ⇒ 测量即时刷新 ✓。
  Animation<double>? _routeAnimation;

  void _onRouteTick() {
    if (mounted) setState(() {});
  }

  void _syncRouteAnimation() {
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeListener(_onRouteTick);
    _routeAnimation = animation;
    _routeAnimation?.addListener(_onRouteTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRouteAnimation();
    _resolveImage();
  }

  @override
  void dispose() {
    _routeAnimation?.removeListener(_onRouteTick);
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _resolveImage() {
    if (!AppBackground.isActive) {
      _image = null;
      _sliceCachedImage = null;
      _sliceCachedPath = null;
      return;
    }
    final file = currentBackgroundImageFile();
    if (file == null) {
      _image = null;
      _sliceCachedImage = null;
      _sliceCachedPath = null;
      return;
    }
    if (_path == file.path && _image != null) return; // 同一张图不重复解析
    _path = file.path;
    // ⭐ 首帧同步命中缓存 ⇒ 本帧就能画出图（消除"先白一下再出图"）
    if (_sliceCachedPath == file.path && _sliceCachedImage != null) {
      _image = _sliceCachedImage;
    }
    final stream = FileImage(
      file,
    ).resolve(createLocalImageConfiguration(context));
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      _sliceCachedImage = info.image;

      _sliceCachedPath = file.path;

      setState(() => _image = info.image);
    }, onError: (_, _) {});
    _stream = stream..addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    // 建立设置依赖：背景图/底色/透明度/显示方式变化时精准重建
    AppSettingsScope.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final measured = box.localToGlobal(Offset.zero);
      if (measured != _offsetInWindow) {
        setState(() => _offsetInWindow = measured);
      }
    });
    final scheme = Theme.of(context).colorScheme;
    final fitSetting =
        appdata.settings['backgroundImageFit'] as String? ?? 'cover';
    final base =
        resolveColorSettingValue(
          appdata.settings['backgroundColor'] as String? ?? 'transparent',
        ) ??
        scheme.surface;
    final opacity =
        ((appdata.settings['backgroundImageOpacity'] as num?)?.toDouble() ??
                1.0)
            .clamp(0.0, 1.0);
    return CustomPaint(
      painter: _BackgroundSlicePainter(
        image: _image,
        offsetInWindow: _offsetInWindow ?? Offset.zero,
        windowSize: MediaQuery.sizeOf(context),
        baseColor: base,
        opacity: opacity,
        fit: backgroundBoxFitOf(fitSetting),
        isRepeat: fitSetting == 'repeat',
      ),
    );
  }
}

class _BackgroundSlicePainter extends CustomPainter {
  _BackgroundSlicePainter({
    required this.image,
    required this.offsetInWindow,
    required this.windowSize,
    required this.baseColor,
    required this.opacity,
    required this.fit,
    required this.isRepeat,
  });

  final ui.Image? image;
  final Offset offsetInWindow;
  final Size windowSize;
  final Color baseColor;
  final double opacity;
  final BoxFit fit;
  final bool isRepeat;

  @override
  void paint(Canvas canvas, Size size) {
    // 底色（与全窗背景层同源）
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);
    final img = image;
    if (img == null) return;
    // ⭐ 修复（2026-10-10 用户实测 ✓）：**位置改用"本帧绘制时的 canvas 变换"同步取得** ✗→✓ ——
    // 原先用帧后测量的 `offsetInWindow` ✗：绘制时拿到的是**上一帧**的位置 ⇒ 面板本帧移动多少，
    // 整窗矩形就落后多少 ⇒ 滑动前缘露出**一条底色（无背景色时=主题白）** ✗。
    // 宽度＝该帧位移 ⇒ `fastOutSlowIn` 曲线中间位移最大 ⇒ **白条中间最宽** ✓，与用户观察逐点吻合 ✓。
    // canvas 变换在**本帧绘制时**有效 ⇒ 无滞后 ✓；测不准时退回测量值兜底 ✓。
    // 注：`canvas.getTransform()` 返回 `Float64List`（不是 Matrix4 ✓），需显式转换 ✓。
    final m = Matrix4.fromFloat64List(canvas.getTransform());
    final scale = m.getMaxScaleOnAxis();
    final origin = scale > 0
        ? Offset(m.storage[12] / scale, m.storage[13] / scale)
        : offsetInWindow;
    // 整窗矩形平移到本组件坐标系 → 与全窗背景逐像素对齐
    final rect = Rect.fromLTWH(
      -origin.dx,
      -origin.dy,
      windowSize.width,
      windowSize.height,
    );
    paintImage(
      canvas: canvas,
      rect: rect,
      image: img,
      fit: isRepeat ? BoxFit.none : fit,
      repeat: isRepeat ? ImageRepeat.repeat : ImageRepeat.noRepeat,
      alignment: isRepeat ? Alignment.topLeft : Alignment.center,
      opacity: opacity,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_BackgroundSlicePainter old) =>
      // ⭐ 位置已改由"本帧 canvas 变换"决定 ✗ ⇒ **字段相同不代表画面相同**（组件仍在被平移 ✓）
      // ⇒ 统一返回 true ✓（仅在重建时被询问，并非每帧 ✓），确保过渡期间切片按新位置重绘 ✓。
      true;
}
