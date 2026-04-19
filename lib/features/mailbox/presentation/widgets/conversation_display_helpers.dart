import '../../domain/entities/mail_conversation.dart';

String displayConversationSubject(String subject) {
  final original = subject.trim();
  if (original.isEmpty) {
    return '(No subject)';
  }

  var display = original;
  var previous = '';
  final prefixPattern = RegExp(r'^(re|fw|fwd):\s*', caseSensitive: false);
  while (display != previous) {
    previous = display;
    display = display.replaceFirst(prefixPattern, '').trimLeft();
  }

  return display.trim().isEmpty ? original : display.trim();
}

List<MailConversationMessage> conversationTimelinePreview(
  MailConversation conversation,
) {
  return conversation.messages;
}
