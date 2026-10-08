import 'dart:convert';
import 'dart:io';

/// 外观规则守卫（棘轮式）——**只许变好，不许变差**。
///
/// 用法：
///   dart run tool/appearance_guard.dart          # 校验（超出基线则退出码 1）
///   dart run tool/appearance_guard.dart --update # 重新采样并写回基线
///
/// 规则见 `doc-private/03-implementation/07-background-and-color-picker.md` 的「外观决策表」：
/// 圆角用 `AppRadius`、间距用 `AppSpace`、透明度用 `AppOpacity`、动效用 `AppMotion`、
/// 含文字的容器用 `minHeight` 而非固定 `height`、桌面顶部边界用 `AppTopBar`。
void main(List<String> args) {
  final root = Directory('lib');
  if (!root.existsSync()) {
    stderr.writeln('请在项目根目录（app/）执行本脚本');
    exit(2);
  }

  final patterns = <String, RegExp>{
    '硬编码圆角': RegExp(r'BorderRadius\.circular\([0-9]|Radius\.circular\([0-9]'),
    '硬编码时长': RegExp(r'Duration\(milliseconds:\s*[0-9]'),
    // ⭐ C8 修复（审计 AP1-C8 ✓）：原正则**只认** `.withOpacity(0.x)` ✗ →
    // `.toOpacity(0.x)`（本项目自加的扩展 ✓）/ `.withValues(alpha: 0.x)`（Flutter 3.27+ 推荐 ✓）/
    // `.withAlpha(0x33)` **全部漏网** ✗（实测 51 处 ✓）→ 该条铁律此前**零自动化覆盖** ✓。
    // 本轮**扩正则** ✓，并把**存量**作为新基线**显式记账** ✓（棘轮仍"只许降不许升" ✓ →
    // 之后每改用一次 `AppOpacity` 令牌，该计数就应下降一格 ✓）。
    '裸透明度': RegExp(
      r'\.withOpacity\(0\.[0-9]+\)|\.toOpacity\(0\.[0-9]+\)|'
      r'\.withValues\(\s*alpha:\s*0\.[0-9]+\s*\)|\.withAlpha\(0x?[0-9a-fA-F]{1,2}\)',
    ),
    '固定高度': RegExp(r'(?<!\w)height:\s*[0-9]+(\.[0-9]+)?\s*,'),
    '表面色字面量': RegExp(r'color:\s*Colors\.(white|black|grey|gray)'),
    '硬编码图标尺寸': RegExp(r'(?<!\w)(size|iconSize):\s*[0-9]'),
    '裸间距数值': RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB)\([^)]*[0-9]'),
  };

  final counts = <String, int>{};
  for (final entry in patterns.entries) {
    var n = 0;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('design_tokens.dart')) continue; // 令牌定义本身不计入硬编码
      final text = f.readAsStringSync();
      n += entry.value.allMatches(text).length;
    }
    counts[entry.key] = n;
  }

  final baselineFile = File('tool/appearance_baseline.json');
  if (args.contains('--update') || !baselineFile.existsSync()) {
    baselineFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(counts),
    );
    stdout.writeln('已写入基线 ${baselineFile.path}');
    counts.forEach((k, v) => stdout.writeln('  $k: $v'));
    return;
  }

  final baseline = (jsonDecode(baselineFile.readAsStringSync()) as Map)
      .cast<String, dynamic>();
  var failed = false;
  for (final entry in counts.entries) {
    final base = (baseline[entry.key] as num?)?.toInt();
    final cur = entry.value;
    if (base == null) {
      stdout.writeln('新增指标 ${entry.key}: $cur（基线缺失，请 --update）');
      failed = true;
    } else if (cur > base) {
      stderr.writeln('✗ ${entry.key} 由 $base 增加到 $cur —— 请改用令牌（见外观决策表）');
      failed = true;
    } else {
      stdout.writeln('✓ ${entry.key}: $cur（基线 $base）');
    }
  }
  if (failed) {
    stderr.writeln(
      '\n外观规则守卫未通过：新增代码请使用 AppRadius/AppSpace/AppOpacity/AppMotion/AppTopBar。',
    );
    exit(1);
  }
  stdout.writeln('\n外观规则守卫通过。');
}
