part of 'settings_page.dart';

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});

  @override
  State<DebugPage> createState() => DebugPageState();
}

class DebugPageState extends State<DebugPage> {
  final controller = TextEditingController();

  var result = "";

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Debug".tl)),
        _CallbackSetting(
          title: "Reload Configs".tl,
          actionTitle: "Reload".tl,
          callback: () {
            ComicSourceManager().reload();
          },
        ).toSliver(),
        _CallbackSetting(
          title: "Open Log".tl,
          callback: () {
            // ⭐ AO1（同款修法 ✓）：推在**当前（右栏内层）Navigator** ✓ 而非根 Navigator 的全屏弹层 ✗
            // → 左侧设置栏不被遮 ✓，点其它设置项一次即切换 ✓。
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LogsPage()));
          },
          actionTitle: 'Open'.tl,
        ).toSliver(),
        _SwitchSetting(
          title: "Ignore Certificate Errors".tl,
          settingKey: "ignoreBadCertificate",
        ).toSliver(),
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                "JS Evaluator",
                style: TextStyle(fontSize: 16),
              ).toAlign(Alignment.centerLeft).paddingLeft(16),
              Container(
                width: double.infinity,
                height: 200,
                margin: const EdgeInsets.symmetric(
                  vertical: AppSpace.sm,
                  horizontal: AppSpace.lg,
                ),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlign: TextAlign.start,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(AppSpace.sm),
                  ),
                ),
              ),
              // P8：标准 `TextButton` → 应用自绘 `Button`（一套体系 ✓，高度锁 32 ✓）
              Button.normal(
                onPressed: () {
                  try {
                    var res = JsEngine().runCode(controller.text, "<debug>");
                    setState(() {
                      result = res.toString();
                    });
                  } catch (e) {
                    setState(() {
                      result = e.toString();
                    });
                  }
                },
                child: const Text("Run"),
              ).toAlign(Alignment.centerRight).paddingRight(16),
              const Text(
                "Result",
                style: TextStyle(fontSize: 16),
              ).toAlign(Alignment.centerLeft).paddingLeft(16),
              Container(
                width: double.infinity,
                height: 200,
                margin: const EdgeInsets.symmetric(
                  vertical: AppSpace.sm,
                  horizontal: AppSpace.lg,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colorScheme.outline),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SingleChildScrollView(child: Text(result).paddingAll(4)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
