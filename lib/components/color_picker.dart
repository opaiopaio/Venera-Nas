part of 'components.dart';

// 颜色设置值的编码约定：
//  - 'system'      跟随系统
//  - 'transparent' 透明
//  - '#RRGGBB'     具体颜色
// 兼容历史命名值：red / pink / purple / green / orange / blue / yellow / cyan

const Map<String, Color> _kNamedColorSettingValues = {
  'red': Colors.red,
  'pink': Colors.pink,
  'purple': Colors.purple,
  'green': Colors.green,
  'orange': Colors.orange,
  'blue': Colors.blue,
  'yellow': Colors.yellow,
  'cyan': Colors.cyan,
};

/// 解析颜色设置值。`system` / `transparent` / 空 返回 null（表示非具体颜色）。
Color? resolveColorSettingValue(String? value) {
  if (value == null || value.isEmpty) return null;
  if (value == 'system' || value == 'transparent') return null;
  if (value.startsWith('#')) return _hexToColor(value);
  return _kNamedColorSettingValues[value];
}

/// 将颜色编码为设置值 `#RRGGBB`。
String colorToSettingValue(Color color) => _colorToHex(color);

String _colorToHex(Color color) {
  final v = color.toARGB32();
  final r = (v >> 16) & 0xFF;
  final g = (v >> 8) & 0xFF;
  final b = v & 0xFF;
  return '#${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

Color? _hexToColor(String value) {
  var t = value.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 3) {
    t = t.split('').map((e) => '$e$e').join();
  }
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// 透明色的棋盘格小图（用于色块预览）。
class _TransparentSwatchPainter extends CustomPainter {
  const _TransparentSwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFFBDBDBD);
    canvas.drawRect(Offset.zero & size, light);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()) % 2 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 颜色设置行：右侧显示「黑色描边」的颜色方块，点击进入二级选色页。
class ColorSettingTile extends StatelessWidget {
  const ColorSettingTile({
    super.key,
    required this.title,
    required this.settingValue,
    required this.onPicked,
    this.allowSystem = false,
    this.allowTransparent = false,
  });

  final String title;

  /// 当前设置值：`system` / `transparent` / `#RRGGBB`（兼容旧命名值）。
  final String settingValue;

  final void Function(String value) onPicked;

  final bool allowSystem;

  final bool allowTransparent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTransparent = settingValue == 'transparent';
    final isSystem = settingValue == 'system';
    Color? preview;
    if (isSystem) {
      preview = scheme.primary;
    } else if (!isTransparent) {
      preview = resolveColorSettingValue(settingValue) ?? scheme.primary;
    }

    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isTransparent
                  ? Colors.white
                  : (preview ?? Colors.transparent),
              border: Border.all(color: Colors.black, width: 1.5),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: isTransparent
                ? const CustomPaint(painter: _TransparentSwatchPainter())
                : null,
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () {
        showPopUpWidget(
          context,
          ColorPickerPage(
            title: title,
            initial: settingValue,
            allowSystem: allowSystem,
            allowTransparent: allowTransparent,
            onPick: onPicked,
          ),
        );
      },
    );
  }
}

/// 二级选色页：左侧预设色，右侧调色圆盘 + RGB / 颜色代码输入。
class ColorPickerPage extends StatefulWidget {
  const ColorPickerPage({
    super.key,
    required this.title,
    required this.initial,
    required this.onPick,
    this.allowSystem = false,
    this.allowTransparent = false,
  });

  final String title;

  final String initial;

  final void Function(String value) onPick;

  final bool allowSystem;

  final bool allowTransparent;

  @override
  State<ColorPickerPage> createState() => _ColorPickerPageState();
}

class _ColorPickerPageState extends State<ColorPickerPage> {
  static const List<Color> _presets = [
    Color(0xFFF44336),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF673AB7),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF03A9F4),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFF8BC34A),
    Color(0xFFCDDC39),
    Color(0xFFFFEB3B),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFF795548),
    Color(0xFF9E9E9E),
    Color(0xFF607D8B),
    Color(0xFF000000),
    Color(0xFFFFFFFF),
  ];

  /// 'system' / 'transparent' / null(自定义颜色)
  String? _special;

  late HSVColor _hsv;

  late TextEditingController _rCtl;
  late TextEditingController _gCtl;
  late TextEditingController _bCtl;
  late TextEditingController _hexCtl;

  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    if (v == 'system' && widget.allowSystem) {
      _special = 'system';
    } else if (v == 'transparent' && widget.allowTransparent) {
      _special = 'transparent';
    }
    _hsv = HSVColor.fromColor(resolveColorSettingValue(v) ?? Colors.blue);
    _rCtl = TextEditingController();
    _gCtl = TextEditingController();
    _bCtl = TextEditingController();
    _hexCtl = TextEditingController();
    _syncFields();
  }

  @override
  void dispose() {
    _rCtl.dispose();
    _gCtl.dispose();
    _bCtl.dispose();
    _hexCtl.dispose();
    super.dispose();
  }

  Color get _currentColor => _hsv.toColor();

  void _syncFields() {
    _syncing = true;
    if (_special == null) {
      final v = _currentColor.toARGB32();
      _rCtl.text = '${(v >> 16) & 0xFF}';
      _gCtl.text = '${(v >> 8) & 0xFF}';
      _bCtl.text = '${v & 0xFF}';
      _hexCtl.text = _colorToHex(_currentColor);
    } else {
      _rCtl.text = '';
      _gCtl.text = '';
      _bCtl.text = '';
      _hexCtl.text = '';
    }
    _syncing = false;
  }

  void _onRgbChanged() {
    if (_syncing) return;
    final r = (int.tryParse(_rCtl.text) ?? 0).clamp(0, 255);
    final g = (int.tryParse(_gCtl.text) ?? 0).clamp(0, 255);
    final b = (int.tryParse(_bCtl.text) ?? 0).clamp(0, 255);
    final color = Color.fromARGB(255, r, g, b);
    setState(() {
      _special = null;
      _hsv = HSVColor.fromColor(color);
    });
    _syncing = true;
    _hexCtl.text = _colorToHex(color);
    _syncing = false;
  }

  void _onHexChanged(String s) {
    if (_syncing) return;
    final color = _hexToColor(s);
    if (color == null) return;
    setState(() {
      _special = null;
      _hsv = HSVColor.fromColor(color);
    });
    _syncing = true;
    final v = color.toARGB32();
    _rCtl.text = '${(v >> 16) & 0xFF}';
    _gCtl.text = '${(v >> 8) & 0xFF}';
    _bCtl.text = '${v & 0xFF}';
    _syncing = false;
  }

  void _apply() {
    final value = _special ?? _colorToHex(_currentColor);
    widget.onPick(value);
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopUpWidgetScaffold(
      title: widget.title,
      tailing: [
        TextButton.icon(
          icon: const Icon(Icons.check),
          label: Text("Done".tl),
          onPressed: _apply,
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 430;
          final presets = _buildPresets(context);
          final editor = _buildEditor(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: presets),
                      const SizedBox(width: 16),
                      Expanded(child: editor),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [presets, const SizedBox(height: 16), editor],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildPresets(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Preset colors".tl, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (widget.allowSystem)
              _specialChip(
                context,
                label: "Follow system".tl,
                value: 'system',
                icon: Icons.brightness_auto,
              ),
            if (widget.allowTransparent)
              _specialChip(
                context,
                label: "Transparent".tl,
                value: 'transparent',
                isTransparent: true,
              ),
            for (final c in _presets) _colorCircle(context, c),
          ],
        ),
      ],
    );
  }

  Widget _specialChip(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
    bool isTransparent = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _special == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _special = value;
          _syncFields();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.tiny,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTransparent)
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black54),
                  borderRadius: BorderRadius.circular(3),
                ),
                clipBehavior: Clip.antiAlias,
                child: const CustomPaint(painter: _TransparentSwatchPainter()),
              )
            else if (icon != null)
              Icon(icon, size: AppIconSize.xs),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _colorCircle(BuildContext context, Color c) {
    final scheme = Theme.of(context).colorScheme;
    final selected =
        _special == null && _currentColor.toARGB32() == c.toARGB32();
    return GestureDetector(
      onTap: () {
        setState(() {
          _special = null;
          _hsv = HSVColor.fromColor(c);
          _syncFields();
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final active = _special == null;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          width: double.infinity,
          decoration: BoxDecoration(
            color: active
                ? _currentColor
                : (_special == 'system' ? scheme.primary : Colors.white),
            border: Border.all(color: Colors.black, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: _special == 'transparent'
              ? const CustomPaint(painter: _TransparentSwatchPainter())
              : null,
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: active ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !active,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: SizedBox(
                    width: 176,
                    height: 176,
                    child: _ColorWheel(
                      hsv: _hsv,
                      onChanged: (h) {
                        setState(() {
                          _hsv = h;
                          _syncFields();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("Brightness".tl),
                    Expanded(
                      child: Slider(
                        value: _hsv.value,
                        onChanged: (v) {
                          setState(() {
                            _hsv = _hsv.withValue(v);
                            _syncFields();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _numberField(_rCtl, "R"),
                    const SizedBox(width: 8),
                    _numberField(_gCtl, "G"),
                    const SizedBox(width: 8),
                    _numberField(_bCtl, "B"),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hexCtl,
                  decoration: InputDecoration(
                    labelText: "Color code".tl,
                    hintText: '#RRGGBB',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onHexChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController ctl, String label) {
    return Expanded(
      child: TextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => _onRgbChanged(),
      ),
    );
  }
}

/// 调色圆盘：角度 = 色相，半径 = 饱和度。
class _ColorWheel extends StatelessWidget {
  const _ColorWheel({required this.hsv, required this.onChanged});

  final HSVColor hsv;

  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return GestureDetector(
          onPanDown: (d) => _handle(d.localPosition, side),
          onPanUpdate: (d) => _handle(d.localPosition, side),
          child: CustomPaint(
            size: Size(side, side),
            painter: _ColorWheelPainter(hsv),
          ),
        );
      },
    );
  }

  void _handle(Offset p, double side) {
    final center = Offset(side / 2, side / 2);
    final radius = side / 2;
    if (radius <= 0) return;
    final dx = p.dx - center.dx;
    final dy = p.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final sat = (dist / radius).clamp(0.0, 1.0);
    var hue = math.atan2(dy, dx) * 180 / math.pi;
    hue = (hue + 360) % 360;
    onChanged(HSVColor.fromAHSV(1, hue, sat, hsv.value));
  }
}

class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final hueColors = <Color>[
      for (int i = 0; i <= 360; i += 30)
        HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hueColors).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }

    final markerAngle = hsv.hue * math.pi / 180;
    final markerRadius = hsv.saturation * radius;
    final marker =
        center +
        Offset(
          math.cos(markerAngle) * markerRadius,
          math.sin(markerAngle) * markerRadius,
        );
    canvas.drawCircle(
      marker,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      marker,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
