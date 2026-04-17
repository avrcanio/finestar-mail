import 'mail_message_summary.dart';

class MailMessagePage {
  const MailMessagePage({
    required this.messages,
    required this.hasMore,
    this.nextBeforeUid,
  });

  final List<MailMessageSummary> messages;
  final bool hasMore;
  final String? nextBeforeUid;
}
