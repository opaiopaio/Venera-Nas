import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/app_settings_scope.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/favorites.dart';
import 'package:venera_nas/pages/favorites/favorites_page.dart';
import 'package:venera_nas/utils/translations.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  testWidgets('probe real sidebar ink rect vs mask rect', (tester) async {
    try {
      AppTranslation.translations = <String, Map<String, String>>{};
    } catch (_) {}
    final tempDir = Directory.systemTemp.createTempSync('venera-sb-ink-');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    App.dataPath = tempDir.path;
    // ⚠️ 真实异步初始化必须放在 `runAsync` 里 ✗→✓（否则 fake async 下会挂住 ✓ 已实测）。
    await tester.runAsync(() async {
      await appdata.init();
      await LocalFavoritesManager().init();
    });

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppSettingsScope(
        child: MaterialApp(home: Scaffold(body: FavoritesPage())),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    debugPrint('PROBE texts=${find.byType(Text).evaluate().length}');
    for (final e in find.byType(Text).evaluate()) {
      debugPrint('PROBE text=${(e.widget as Text).data}');
    }
    final all = find.text('All');
    if (all.evaluate().isEmpty) {
      debugPrint('PROBE no All row');
      return;
    }
    final inkFinder = find.ancestor(of: all, matching: find.byType(InkWell));
    final inkSize = (inkFinder.evaluate().first.renderObject as RenderBox).size;
    final decoFinder = find.descendant(
      of: inkFinder,
      matching: find.byType(DecoratedBox),
    );
    debugPrint('PROBE decoratedCount=${decoFinder.evaluate().length}');
    final decoSize = (decoFinder.evaluate().first.renderObject as RenderBox)
        .size;
    final lvSize =
        (find.byType(ListView).evaluate().first.renderObject as RenderBox).size;
    debugPrint('PROBE listView=$lvSize');
    debugPrint('PROBE inkWellRect=$inkSize');
    debugPrint('PROBE maskRect(decoratedBox)=$decoSize');
  });
}
