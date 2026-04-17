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
    required this.rootMessage,
    required this.replies,
    required this.latestDate,
    this.timelineMessages = const [],
  });

  final String id;
  final int messageCount;
  final int replyCount;
  final bool hasUnread;
  final bool hasAttachments;
  final bool hasVisibleAttachments;
  final List<MailConversationParticipant> participants;
  final MailMessageSummary rootMessage;
  final List<MailMessageSummary> replies;
  final DateTime latestDate;
  final List<MailConversationMessage> timelineMessages;

  List<MailConversationMessage> get messages {
    if (timelineMessages.isNotEmpty) {
      return timelineMessages;
    }
    return [
      MailConversationMessage(
        message: rootMessage,
        direction: MailConversationDirection.inbound,
      ),
      for (final reply in replies)
        MailConversationMessage(
          message: reply,
          direction: MailConversationDirection.inbound,
        ),
    ];
  }
}
