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
    this.isImportant = false,
    this.isPinned = false,
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
  final bool isImportant;
  final bool isPinned;

  MailMessageSummary copyWith({
    String? id,
    String? folderId,
    String? subject,
    String? sender,
    String? preview,
    DateTime? receivedAt,
    bool? isRead,
    bool? hasAttachments,
    int? sequence,
    bool? isImportant,
    bool? isPinned,
  }) {
    return MailMessageSummary(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      subject: subject ?? this.subject,
      sender: sender ?? this.sender,
      preview: preview ?? this.preview,
      receivedAt: receivedAt ?? this.receivedAt,
      isRead: isRead ?? this.isRead,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      sequence: sequence ?? this.sequence,
      isImportant: isImportant ?? this.isImportant,
      isPinned: isPinned ?? this.isPinned,
    );
  }
}
