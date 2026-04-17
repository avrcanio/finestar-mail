import 'mail_message_summary.dart';

enum MailConversationDirection { inbound, outbound }

class MailConversationParticipant {
  const MailConversationParticipant({required this.name, required this.email});

  final String name;
  final String email;
}

class MailConversationMessage {
  const MailConversationMessage({
    required this.message,
    required this.direction,
  });

  final MailMessageSummary message;
  final MailConversationDirection direction;
}

class MailConversation {
  const MailConversation({
    required this.id,
    required this.messageCount,
    required this.replyCount,
    required this.hasUnread,
    required this.hasAttachments,
    required this.hasVisibleAttachments,
    required this.participants,
    required this.messages,
    required this.latestDate,
  });

  final String id;
  final int messageCount;
  final int replyCount;
  final bool hasUnread;
  final bool hasAttachments;
  final bool hasVisibleAttachments;
  final List<MailConversationParticipant> participants;
  final List<MailConversationMessage> messages;
  final DateTime latestDate;
}
