import 'dart:io';
import 'dart:typed_data';

import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:path/path.dart' as p;

class ScannedDocumentImage {
  const ScannedDocumentImage({
    required this.bytes,
    required this.contentType,
    required this.filename,
  });

  final Uint8List bytes;
  final String contentType;
  final String filename;
}

class DocumentScannerService {
  Future<ScannedDocumentImage?> scanFirstPageAsImage() async {
    final paths = await DocumentScanner.scan();
    if (paths == null || paths.isEmpty) {
      return null;
    }

    final firstPath = paths.first.trim();
    if (firstPath.isEmpty) {
      return null;
    }

    final file = File(firstPath);
    final bytes = await file.readAsBytes();
    final filename = p.basename(firstPath);
    final contentType = _contentTypeFromPath(firstPath) ?? 'image/jpeg';
    return ScannedDocumentImage(
      bytes: bytes,
      contentType: contentType,
      filename: filename.isEmpty ? 'receipt.jpg' : filename,
    );
  }

  String? _contentTypeFromPath(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return null;
    }
  }
}

