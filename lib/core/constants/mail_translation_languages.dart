/// ISO-style codes shared by message-detail translation and compose translation.
/// Order is stable for pickers (SimpleDialog / modal lists).
const String kMailTranslationDefaultLanguageCode = 'hr';

const Map<String, String> kMailTranslationLanguageLabels = {
  'hr': 'Croatian',
  'en': 'English',
  'es': 'Spanish',
  'de': 'German',
  'fr': 'French',
  'it': 'Italian',
  'pt': 'Portuguese',
  'zh': 'Chinese',
};

String mailTranslationLanguageLabel(String code) {
  final key = code.trim().toLowerCase();
  return kMailTranslationLanguageLabels[key] ?? code;
}
