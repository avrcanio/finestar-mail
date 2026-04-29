import 'dart:async';

import 'package:flutter/services.dart';

class SharedFile {
  const SharedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;

  static SharedFile? tryParse(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final path = value['path'];
    final name = value['name'];
    final mimeType = value['mimeType'];
    final sizeBytes = value['sizeBytes'];
    if (path is! String || path.trim().isEmpty) {
      return null;
    }
    if (name is! String || name.trim().isEmpty) {
      return null;
    }
    if (mimeType is! String || mimeType.trim().isEmpty) {
      return null;
    }
    final parsedSize = sizeBytes is int ? sizeBytes : int.tryParse('$sizeBytes');
    if (parsedSize == null || parsedSize < 0) {
      return null;
    }
    return SharedFile(
      path: path,
      name: name,
      mimeType: mimeType,
      sizeBytes: parsedSize,
    );
  }
}

class ShareIntentService {
  static const _methodChannel = MethodChannel('hr.finestar.mail/share_intent');
  static const _eventChannel = EventChannel(
    'hr.finestar.mail/share_intent_events',
  );

  Stream<List<SharedFile>> sharedFilesStream() {
    return _eventChannel.receiveBroadcastStream().map(_parseFiles).handleError((
      _,
    ) {});
  }

  Future<List<SharedFile>> getInitialSharedFiles() async {
    try {
      final raw = await _methodChannel.invokeMethod<dynamic>(
        'getInitialSharedFiles',
      );
      return _parseFiles(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  List<SharedFile> _parseFiles(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map(SharedFile.tryParse).whereType<SharedFile>().toList();
  }
}

