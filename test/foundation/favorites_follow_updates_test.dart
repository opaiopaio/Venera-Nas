import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera_nas/foundation/app.dart';
import 'package:venera_nas/foundation/appdata.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/favorites.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

FavoriteItem _comic(String id) {
  return FavoriteItem(
    id: id,
    name: 'Comic $id',
    coverPath: 'cover-$id',
    author: 'Author $id',
    type: ComicType.local,
    tags: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalFavoritesManager manager;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('venera-favorites-test-');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    App.dataPath = tempDir.path;

    appdata.settings['followUpdatesFolder'] = null;
    manager = LocalFavoritesManager();
    await appdata.init();
    await manager.init();
    await pumpEventQueue();
  });

  tearDown(() {
    if (manager.isInitialized) {
      manager.close();
    }
    LocalFavoritesManager.cache = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('notifies listeners when a comic gains a new follow update', () {
    const folder = 'Follow Updates';
    manager.createFolder(folder);
    manager.prepareTableForFollowUpdates(folder);
    manager.addComic(folder, _comic('comic-1'), null, 'chapter-1');

    var notifications = 0;
    manager.addListener(() {
      notifications++;
    });

    manager.updateUpdateTime(folder, 'comic-1', ComicType.local, 'chapter-2');

    expect(manager.countUpdates(folder), 1);
    expect(notifications, 1);
  });

  test('notifies listeners when marking an updated comic as read', () {
    const folder = 'Follow Updates';
    manager.createFolder(folder);
    manager.prepareTableForFollowUpdates(folder);
    manager.addComic(folder, _comic('comic-1'), null, 'chapter-1');
    manager.updateUpdateTime(folder, 'comic-1', ComicType.local, 'chapter-2');
    appdata.settings['followUpdatesFolder'] = folder;

    var notifications = 0;
    manager.addListener(() {
      notifications++;
    });

    manager.markAsRead('comic-1', ComicType.local);

    expect(manager.countUpdates(folder), 0);
    expect(notifications, 1);
  });
}


