class MailMessageTranslation {
  const MailMessageTranslation({
    required this.folder,
    required this.uid,
    required this.messageIdHeader,
    required this.targetLanguage,
    required this.sourceLanguage,
    required this.translatedSubject,
    required this.translatedText,
    required this.translatedHtml,
    required this.cached,
    required this.truncated,
    required this.model,
  });

  final String folder;
  final String uid;
  final String messageIdHeader;
  final String targetLanguage;
  final String sourceLanguage;
  final String translatedSubject;
  final String translatedText;
  final String translatedHtml;
  final bool cached;
  final bool truncated;
  final String model;
}

