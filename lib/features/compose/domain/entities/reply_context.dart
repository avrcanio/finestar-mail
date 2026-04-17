enum ReplyAction { reply, replyAll, forward }

class ForwardedAttachmentRef {
  const ForwardedAttachmentRef({
    required this.attachmentId,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String attachmentId;
  final String fileName;
  final int? sizeBytes;
  final String mimeType;
}

class ReplyContext {
  const ReplyContext({
    required this.messageId,
    required this.targetMessageId,
    required this.subject,
    required this.action,
    required this.recipients,
    required this.originalSender,
    required this.originalReceivedAt,
    required this.originalBody,
    this.originalMessageIdHeader,
    this.originalReferencesHeader,
    this.forwardSourceFolder,
    this.forwardSourceUid,
    this.forwardedAttachments = const [],
  });

  final String messageId;
  final String targetMessageId;
  final String subject;
  final ReplyAction action;
  final List<String> recipients;
  final String originalSender;
  final DateTime originalReceivedAt;
  final String originalBody;
  final String? originalMessageIdHeader;
  final String? originalReferencesHeader;
  final String? forwardSourceFolder;
  final String? forwardSourceUid;
  final List<ForwardedAttachmentRef> forwardedAttachments;
}
