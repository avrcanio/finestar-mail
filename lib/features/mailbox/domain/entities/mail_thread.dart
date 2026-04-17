import 'mail_message_attachment.dart';

class MailThread {
  const MailThread({
    required this.subject,
    required this.selectedMessageId,
    required this.messages,
  });

  final String subject;
  final String selectedMessageId;
  final List<MailThreadMessage> messages;
}

class MailThreadMessage {
  const MailThreadMessage({
    required this.id,
    required this.folderId,
    required this.folderName,
    this.folderPath = '',
    this.backendUid,
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.bodyPlain,
    required this.bodyHtml,
    required this.receivedAt,
    required this.messageIdHeader,
    required this.inReplyToHeader,
    required this.referencesHeader,
    this.attachments = const [],
  });

  final String id;
  final String folderId;
  final String folderName;
  final String folderPath;
  final String? backendUid;
  final String subject;
  final String sender;
  final List<String> recipients;
  final String bodyPlain;
  final String? bodyHtml;
  final DateTime receivedAt;
  final String? messageIdHeader;
  final String? inReplyToHeader;
  final String? referencesHeader;
  final List<MailMessageAttachment> attachments;

  String get visibleBody => splitQuotedText(bodyPlain).visibleBody;

  String? get quotedBody => splitQuotedText(bodyPlain).quotedBody;
}

class QuotedTextParts {
  const QuotedTextParts({required this.visibleBody, required this.quotedBody});

  final String visibleBody;
  final String? quotedBody;
}

QuotedTextParts splitQuotedText(String body) {
  final normalized = body.replaceAll('\r\n', '\n');
  final quotePatterns = [
    RegExp(r'\nOn .+ wrote:\s*\n', caseSensitive: false),
    RegExp(r'\nDana .+ napisao/la je:\s*\n', caseSensitive: false),
    RegExp(r'\n-+\s*Original Message\s*-+\s*\n', caseSensitive: false),
    RegExp(r'\n-+\s*Forwarded message\s*-+\s*\n', caseSensitive: false),
    RegExp(r'\n>{1,2}\s?'),
  ];

  int? quoteIndex;
  for (final pattern in quotePatterns) {
    final match = pattern.firstMatch(normalized);
    if (match == null) {
      continue;
    }
    if (quoteIndex == null || match.start < quoteIndex) {
      quoteIndex = match.start;
    }
  }

  if (quoteIndex == null) {
    return QuotedTextParts(visibleBody: normalized.trim(), quotedBody: null);
  }

  final visible = normalized.substring(0, quoteIndex).trim();
  final quoted = normalized.substring(quoteIndex).trim();
  return QuotedTextParts(
    visibleBody: visible.isEmpty ? normalized.trim() : visible,
    quotedBody: quoted.isEmpty ? null : quoted,
  );
}
