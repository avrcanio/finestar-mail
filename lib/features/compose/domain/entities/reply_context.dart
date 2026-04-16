enum ReplyAction { reply, replyAll, forward }

class ReplyContext {
  const ReplyContext({
    required this.messageId,
    required this.subject,
    required this.action,
    required this.recipients,
  });

  final String messageId;
  final String subject;
  final ReplyAction action;
  final List<String> recipients;
}
