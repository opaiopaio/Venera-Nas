import 'dart:async' show Future;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:venera_nas/foundation/cache_manager.dart';
import 'package:venera_nas/foundation/js_engine.dart';
import 'package:venera_nas/network/images.dart';
import 'package:venera_nas/network/smb/smb_client.dart';
import 'package:venera_nas/network/smb/smb_config.dart';
import 'package:venera_nas/utils/io.dart';
import 'base_image_provider.dart';
import 'reader_image.dart' as image_provider;
import 'package:venera_nas/foundation/appdata.dart';

class ReaderImageProvider
    extends BaseImageProvider<image_provider.ReaderImageProvider> {
  /// Image provider for normal image.
  const ReaderImageProvider(
    this.imageKey,
    this.sourceKey,
    this.cid,
    this.eid,
    this.page, {
    this.enableResize = false,
    this.onLoadFailed,
  });

  final String imageKey;

  final String? sourceKey;

  final String cid;

  final String eid;

  final int page;

  final void Function()? onLoadFailed;

  @override
  final bool enableResize;

  @override
  Future<Uint8List> load(chunkEvents, checkStop) async {
    Uint8List? imageBytes;
    if (imageKey.startsWith('file://')) {
      var file = File(imageKey.substring(7));
      if (await file.exists()) {
        imageBytes = await file.readAsBytes();
      } else {
        throw "Error: File not found.";
      }
    } else if (imageKey.startsWith('smb://')) {
      // Read from SMB share — connect, read bytes, disconnect.
      // No disk caching: data stays in memory only.
      print('[SMB Reader] loading: $imageKey');
      final config = _parseSmbConfigFromUrl(imageKey);
      final remotePath = _smbFilePathFromUrl(config, imageKey);
      print('[SMB Reader] host=${config.host} share=${config.share} remotePath=$remotePath');
      final client = SmbClient(config: config);
      try {
        await client.connect();
        print('[SMB Reader] connected, calling readFile...');
        imageBytes = await client.readFile(remotePath);
        print('[SMB Reader] readFile done, ${imageBytes.length} bytes');
      } catch (e) {
        print('[SMB Reader] ERROR: $e');
        rethrow;
      } finally {
        await client.disconnect();
      }
    } else {
      await for (var event in ImageDownloader.loadComicImage(
        imageKey,
        sourceKey,
        cid,
        eid,
      )) {
        checkStop();
        chunkEvents.add(
          ImageChunkEvent(
            cumulativeBytesLoaded: event.currentBytes,
            expectedTotalBytes: event.totalBytes,
          ),
        );
        if (event.imageBytes != null) {
          imageBytes = event.imageBytes;
          break;
        }
      }
    }
    if (imageBytes == null) {
      throw "Error: Empty response body.";
    }
    if (appdata.settings['enableCustomImageProcessing']) {
      var script = appdata.settings['customImageProcessing'].toString();
      if (!script.contains('function processImage')) {
        return imageBytes;
      }
      var func = JsEngine().runCode('''
        (() => {
          $script
          return processImage;
        })()
      ''');
      if (func is JSInvokable) {
        var autoFreeFunc = JSAutoFreeFunction(func);
        var result = autoFreeFunc([imageBytes, cid, eid, page, sourceKey]);
        if (result is Uint8List) {
          imageBytes = result;
        } else if (result is Future) {
          var futureResult = await result;
          if (futureResult is Uint8List) {
            imageBytes = futureResult;
          }
        } else if (result is Map) {
          var image = result['image'];
          if (image is Uint8List) {
            imageBytes = image;
          } else if (image is Future) {
            JSAutoFreeFunction? onCancel;
            if (result['onCancel'] is JSInvokable) {
              onCancel = JSAutoFreeFunction(result['onCancel']);
            }
            if (onCancel == null) {
              var futureImage = await image;
              if (futureImage is Uint8List) {
                imageBytes = futureImage;
              }
            } else {
              dynamic futureImage;
              image.then((value) {
                futureImage = value;
                futureImage ??= Uint8List(0);
              });
              while (futureImage == null) {
                try {
                  checkStop();
                } catch (e) {
                  onCancel([]);
                  rethrow;
                }
                await Future.delayed(Duration(milliseconds: 50));
              }
              if (futureImage is Uint8List) {
                imageBytes = futureImage;
              }
            }
          }
        }
      }
    }
    return imageBytes!;
  }

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key => "$imageKey@$sourceKey@$cid@$eid@$enableResize";

  @override
  void onLoadError() {
    var cacheKey = "loadComicPages@$sourceKey@$cid@$eid";
    CacheManager().delete(cacheKey);
    onLoadFailed?.call();
  }
}

/// Parse [SmbConfig] from an smb:// URL string.
SmbConfig _parseSmbConfigFromUrl(String url) {
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

/// Extract the file path (relative to the share root) from an smb:// URL.
///
/// For `smb://host/share/dir/subdir/001.jpg`, returns `dir/subdir/001.jpg`.
String _smbFilePathFromUrl(SmbConfig config, String url) {
  final uri = Uri.parse(url);
  final segments = uri.pathSegments;
  // segments[0] = share name, rest = path within share
  if (segments.length <= 1) return '';
  return segments.sublist(1).join('/');
}


