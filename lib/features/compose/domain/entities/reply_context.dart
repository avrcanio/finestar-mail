enum ReplyAction { reply, replyAll, forward }

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
}
