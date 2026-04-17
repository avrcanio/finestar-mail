class MailMessageAttachment {
  const MailMessageAttachment({
    required this.id,
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.disposition,
    required this.isInline,
    this.contentId = '',
    this.isVisible,
  });

  final String id;
  final String filename;
  final String contentType;
  final int? sizeBytes;
  final String? disposition;
  final bool isInline;
  final String contentId;
  final bool? isVisible;
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
