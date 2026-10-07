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

class _BackgroundSliceState extends State<BackgroundSlice> {
  /// 本组件左上角在窗口坐标里的位置。
  Offset? _offsetInWindow;

  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  String? _path;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _resolveImage() {
    if (!AppBackground.isActive) {
      _image = null;
      return;
    }
    final file = currentBackgroundImageFile();
    if (file == null) {
      _image = null;
      return;
    }
    if (_path == file.path && _image != null) return; // 同一张图不重复解析
    _path = file.path;
    final stream = FileImage(
      file,
    ).resolve(createLocalImageConfiguration(context));
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
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
    // 整窗矩形平移到本组件坐标系 → 与全窗背景逐像素对齐
    final rect = Rect.fromLTWH(
      -offsetInWindow.dx,
      -offsetInWindow.dy,
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
      old.image != image ||
      old.offsetInWindow != offsetInWindow ||
      old.windowSize != windowSize ||
      old.baseColor != baseColor ||
      old.opacity != opacity ||
      old.fit != fit ||
      old.isRepeat != isRepeat;
}
