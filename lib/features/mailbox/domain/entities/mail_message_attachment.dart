class MailMessageAttachment {
  const MailMessageAttachment({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.disposition,
    required this.isInline,
  });

  final String id;
  final String filename;
  final String contentType;
  final int? sizeBytes;
  final String? disposition;
  final bool isInline;
}

class DownloadedMailAttachment {
  const DownloadedMailAttachment({
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String filename;
  final String contentType;
  final List<int> bytes;
}
