import 'dart:async' show Future;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_nas/foundation/comic_type.dart';
import 'package:venera_nas/foundation/local.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'local_comic_image.dart' as image_provider;

class LocalComicImageProvider
    extends BaseImageProvider<image_provider.LocalComicImageProvider> {
  /// Image provider for normal image.
  ///
  /// [url] is the url of the image. Local file path is also supported.
  const LocalComicImageProvider(this.comic);

  final LocalComic comic;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    // SMB: read cover from remote share
    if (comic.comicType == ComicType.smb || comic.baseDir.startsWith('smb://')) {
      return _loadSmbCover();
    }

    File? file = comic.coverFile;
    if (!await file.exists()) {
      file = null;
      var dir = Directory(comic.directory);
      if (!await dir.exists()) {
        throw "Error: Comic not found.";
      }
      Directory? firstDir;
      await for (var entity in dir.list()) {
        if (entity is File) {
          if ([
            "jpg",
            "jpeg",
            "png",
            "webp",
            "gif",
            "jpe",
            "jpeg",
          ].contains(entity.extension)) {
            file = entity;
            break;
          }
        } else if (entity is Directory) {
          firstDir ??= entity;
        }
      }
      if (file == null && firstDir != null) {
        await for (var entity in firstDir.list()) {
          if (entity is File) {
            if ([
              "jpg",
              "jpeg",
              "png",
              "webp",
              "gif",
              "jpe",
              "jpeg",
            ].contains(entity.extension)) {
              file = entity;
              break;
            }
          }
        }
      }
    }
    if (file == null) {
      throw "Error: Cover not found.";
    }
    checkStop();
    var data = await file.readAsBytes();
    if (data.isEmpty) {
      throw "Exception: Empty file(${file.path}).";
    }
    return data;
  }

  Future<Uint8List> _loadSmbCover() async {
    final baseDir = comic.baseDir;
    final coverName = comic.cover;

    // Build the full smb:// URL for the cover image.
    // If the cover is already a full URL (starts with smb://), use it directly.
    final String coverUrl;
    if (coverName.startsWith('smb://')) {
      coverUrl = coverName;
    } else {
      // baseDir is smb://host/share/path, cover is "cover.jpg" or similar
      coverUrl = '${baseDir.endsWith('/') ? baseDir : '$baseDir/'}$coverName';
    }

    print('[SMB Cover] loading: $coverUrl');

    final config = _parseSmbConfigFromUrl(baseDir);
    final remoteCoverPath = _smbCoverPathFromUrl(config, coverUrl);

    print('[SMB Cover] host=${config.host} share=${config.share} remotePath=$remoteCoverPath');

    final client = SmbClient(config: config);
    try {
      await client.connect();
      try {
        final data = await client.readFile(remoteCoverPath);
        print('[SMB Cover] readFile done, ${data.length} bytes');
        if (data.isEmpty) {
          throw "Exception: Empty cover file on SMB.";
        }
        return data;
      } on Smb2Exception catch (e) {
        if (e.type != Smb2ErrorType.fileNotFound) rethrow;
        // Cover not found at expected path — search the directory.
        print('[SMB Cover] cover not found at $remoteCoverPath, searching...');
        final smbDir = _smbCoverPathFromUrl(config, baseDir);
        final entries = await client.listDirectory(smbDir);
        // Try cover.* first, then any image
        const exts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'jpe'];
        SmbEntry? found;
        for (final e in entries) {
          if (!e.isFile || !exts.contains(e.extension.toLowerCase())) continue;
          if (e.name.toLowerCase().startsWith('cover')) {
            found = e;
            break;
          }
          found ??= e;
        }
        // If not found in base directory, try first subdirectory (chapter)
        if (found == null) {
          for (final e in entries) {
            if (!e.isDirectory) continue;
            final subEntries = await client.listDirectory(e.path);
            for (final se in subEntries) {
              if (!se.isFile || !exts.contains(se.extension.toLowerCase())) continue;
              found = se;
              break;
            }
            if (found != null) break;
          }
        }
        if (found == null) rethrow;
        final data = await client.readFile(found.path);
        print('[SMB Cover] fallback cover: ${found.path}, ${data.length} bytes');
        return data;
      }
    } finally {
      await client.disconnect();
    }
  }

  static SmbConfig _parseSmbConfigFromUrl(String url) {
    final uri = Uri.parse(url);
    final parts = uri.pathSegments;
    final share = parts.isNotEmpty ? parts.first : '';
    final userInfo = uri.userInfo.split(':');
    return SmbConfig(
      host: uri.host,
      port: uri.hasPort ? uri.port : 445,
      share: share,
      username: userInfo.isNotEmpty ? Uri.decodeComponent(userInfo[0]) : '',
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : '',
    );
  }

  static String _smbCoverPathFromUrl(SmbConfig config, String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.length <= 1) return '';
    return segments.sublist(1).join('/');
  }

  @override
  Future<LocalComicImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "local${comic.id}${comic.comicType.value}";
}


