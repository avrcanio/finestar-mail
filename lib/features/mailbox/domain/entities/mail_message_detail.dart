class MailMessageDetail {
  const MailMessageDetail({
    required this.id,
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.bodyPlain,
    required this.bodyHtml,
    required this.receivedAt,
  });

  final String id;
  final String subject;
  final String sender;
  final List<String> recipients;
  final String bodyPlain;
  final String? bodyHtml;
  final DateTime receivedAt;
}
