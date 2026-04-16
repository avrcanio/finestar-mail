class AttachmentRef {
  const AttachmentRef({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String id;
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final String mimeType;
}
