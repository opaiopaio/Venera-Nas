import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 设置行「遮罩入口」守卫：把隐藏规则固化成测试，防止将来新增设置行又漏遮罩。
///
/// 规则：`lib/pages/**` 里调用**共享设置组件**时，必须满足至少一条 ——
/// ① 传了 `masked:` 参数（组件内部会包 `WindowOverlayBox`）
/// ② 调用后紧跟 `.toSliver()`（容器层包遮罩）
/// ③ 前面 400 字符内出现过 `WindowOverlayBox(`（已被就地包裹）
/// ④ 该行注释含 `// mask-guard: ok`（人工确认的例外，需写明理由）
///
/// 决策表与两个入口见 `doc-private/03-implementation/07-background-and-color-picker.md`。
void main() {
  const components = [
    '_SwitchSetting',
    'SelectSetting',
    '_SliderSetting',
    '_DoubleLineSelectSettings',
    '_EndSelectorSelectSetting',
  ];

  test('lib/pages 下共享设置组件的调用点都已接入遮罩', () {
    final dir = Directory('lib/pages');
    expect(dir.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');

    final problems = <String>[];
    var checked = 0;

    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final name in components) {
        final re = RegExp('(?<![\\w])${RegExp.escape(name)}\\(');
        for (final m in re.allMatches(src)) {
          // 构造函数声明（`const _SwitchSetting({`）不是调用点 → 跳过
          if (src.substring(m.end, m.end + 1) == '{') continue;
          // 平衡括号 → 找到这次调用的结束位置
          var depth = 0;
          var end = -1;
          for (var i = m.end - 1; i < src.length; i++) {
            final c = src[i];
            if (c == '(') {
              depth++;
            } else if (c == ')') {
              depth--;
              if (depth == 0) {
                end = i;
                break;
              }
            }
          }
          if (end < 0) continue;
          checked++;

          final call = src.substring(m.start, end);
          final after = src.substring(end + 1, (end + 16).clamp(0, src.length));
          final before = src.substring((m.start - 400).clamp(0, src.length), m.start);
          final lineStart = src.lastIndexOf('\n', m.start) + 1;
          var lineEnd = src.indexOf('\n', m.start);
          if (lineEnd < 0) lineEnd = src.length;
          final line = src.substring(lineStart, lineEnd);
          final lineNo = '\n'.allMatches(src.substring(0, m.start)).length + 1;

          final ok =
              call.contains('masked:') ||
              after.startsWith('.toSliver()') ||
              before.contains('WindowOverlayBox(') ||
              line.contains('mask-guard: ok');
          if (!ok) problems.add('${f.path}:$lineNo  $name(');
        }
      }
    }

    expect(checked, greaterThan(50), reason: '扫描到的调用点过少，正则可能已失效');
    expect(problems, isEmpty, reason: '以下设置行没有接入遮罩：\n${problems.join('\n')}');
  });
}
