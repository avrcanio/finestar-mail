import 'mail_conversation.dart';

class MailConversationsPage {
  const MailConversationsPage({
    required this.conversations,
    required this.hasMore,
    required this.nextOffset,
  });

  final List<MailConversation> conversations;
  final bool hasMore;
  final int nextOffset;
}
