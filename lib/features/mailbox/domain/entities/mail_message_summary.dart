class MailMessageSummary {
  const MailMessageSummary({
    required this.id,
    required this.folderId,
    required this.subject,
    required this.sender,
    required this.preview,
    required this.receivedAt,
    required this.isRead,
    required this.hasAttachments,
    required this.sequence,
  });

  final String id;
  final String folderId;
  final String subject;
  final String sender;
  final String preview;
  final DateTime receivedAt;
  final bool isRead;
  final bool hasAttachments;
  final int sequence;
}
