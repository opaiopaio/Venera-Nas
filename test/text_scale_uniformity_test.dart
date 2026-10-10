import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_nas/foundation/design_tokens.dart';
import 'package:venera_nas/foundation/widget_utils.dart';

/// ⭐ 本轮（用户实测反馈 ✓）：「字号缩放」一致性守护。
///
/// 用户原话：字号缩放为默认值 1 时与字体选「跟随系统」时，**部分**文字大小不一致 ✓。
/// 读码定性（结论见本轮报告 ✓）：
/// - **第 1 类 字体族度量差异 ✓**：换字体族后同样 `fontSize` 的高度/宽度本就不同 ✓，
///   且缺字回退会让"只有一部分"文字换族 ✓ ⇒ 属字体本身度量，**未改实现** ✗。
/// - **第 2 类 缩放应用不统一 ✗**：本项目没有 `TextScaler.noScaling` ✓、没有裸 `RichText`
///   （不读 `MediaQuery` 的缩放 ✗）、没有 `TextPainter`（默认 `noScaling` ✗）站点 ✓；
///   硬编码字号的 `TextStyle`（`ts.sXX` ✓）仍走 `Text` ⇒ 同样被环境 `textScaler` 缩放 ✓。
/// - **第 3 类 注入路径 ✓**：`main.dart` 的 `MaterialApp.builder` 在最内层包 `textScaler` ✓；
///   `text_style_settings.dart` 的阴影/发光同时注入 `getTheme()` 的 `textTheme` ✓。
///
/// 因此本测试把"统一路径"固化成守护 ✓：
/// ① 静态扫描禁止第 2 类的三类站点回潮 ✗；
/// ② 行为上要求各条文字路径**都**随缩放变化 ✓ —— 任一条不随动即说明又出现"部分不一致" ✗。
void main() {
  group('T-TS1 缩放应用统一（静态）', () {
    test('lib 下不得出现绕过 MediaQuery 缩放的文字站点', () {
      final dir = Directory('lib');
      expect(dir.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');
      // 这三类站点的共同后果：**只有它们的文字不随字号缩放** ⇒ 正是"部分不一致" ✗。
      final banned = <String, RegExp>{
        'TextScaler.noScaling': RegExp(r'TextScaler\.noScaling'),
        '裸 RichText（不读 MediaQuery 缩放）': RegExp(r'(?<![\w.])RichText\('),
        'TextPainter（默认 noScaling）': RegExp(r'(?<![\w.])TextPainter\('),
      };
      final problems = <String>[];
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final e in banned.entries) {
          for (final m in e.value.allMatches(src)) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            problems.add('${f.path}:$line  ${e.key}');
          }
        }
      }
      expect(
        problems,
        isEmpty,
        reason: '以下站点会让"部分文字不随字号缩放"：\n${problems.join('\n')}',
      );
    });
  });

  group('T-TS2 缩放应用统一（行为）', () {
    testWidgets('默认 / 硬编码字号 / 主题字号 / ListTile / SelectableText 全部随缩放变大', (
      tester,
    ) async {
      final normal = await _measureAll(tester, 1.0);
      final scaled = await _measureAll(tester, 1.4);

      // 每条路径都必须**变高** ✓（不变高 = 该路径没吃到 `textScaler` ✗ = "部分不一致" ✗）。
      for (final key in normal.keys) {
        expect(
          scaled[key]! > normal[key]!,
          isTrue,
          reason:
              '$key 在字号 1.4 下未变高（${normal[key]} → ${scaled[key]}）⇒ 未走统一缩放路径',
        );
      }

      // 纯文字路径应与缩放系数**等比** ✓（余量留给不同引擎的字体度量）。
      for (final key in const ['plain', 'hardcoded', 'theme', 'tile']) {
        expect(
          scaled[key]! / normal[key]!,
          closeTo(1.4, 0.15),
          reason: '$key 的高度变化与缩放系数 1.4 不成比例',
        );
      }
    });
  });
}

/// 与 `main.dart` 的 `builder` 同构：**最内层**包 `textScaler` ✓（缩放为 1 时不包 ✓，
/// 与 `main.dart` 的条件一致 ✓），再量各条文字路径的实际渲染尺寸。
Future<Map<String, double>> _measureAll(
  WidgetTester tester,
  double scale,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: const _Probe(),
      builder: (context, child) {
        if (scale == AppTextScale.defaultValue) return child!;
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(AppTextScale.clamp(scale))),
          child: child!,
        );
      },
    ),
  );
  await tester.pumpAndSettle();
  double h(String key) => tester.getSize(find.byKey(Key(key))).height;
  return {
    'plain': h('plain'),
    'hardcoded': h('hardcoded'),
    'theme': h('theme'),
    'tile': h('tile'),
    'selectable': h('selectable'),
  };
}

class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    // 竖排 + 可滚动 ⇒ 缩放变大时不会溢出（溢出会让测试报错，掩盖真实断言）。
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ① 默认文字路径（走 `DefaultTextStyle` ✓）。
            const Text('Sample', key: Key('plain')),
            // ② 硬编码字号路径（`ts.s14` ✓，与全项目 `ts.sXX` 同款 ✓）。
            Text('Sample', key: const Key('hardcoded'), style: ts.s14),
            // ③ 主题文字路径（`getTheme()` 注入过的 `textTheme` ✓）。
            Text(
              'Sample',
              key: const Key('theme'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            // ④ `ListTile` 标题路径（主题烘焙样式 + `listTileTheme` 注入 ✓）。
            const ListTile(title: Text('Sample', key: Key('tile'))),
            // ⑤ `SelectableText` 路径（另一套渲染实现 ✓）。
            const SelectableText('Sample', key: Key('selectable')),
          ],
        ),
      ),
    );
  }
}
