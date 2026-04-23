class ContactSuggestion {
  const ContactSuggestion({
    required this.id,
    required this.email,
    required this.displayName,
    required this.source,
    required this.timesContacted,
    required this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String email;
  final String? displayName;
  final String source;
  final int timesContacted;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayLabel {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? email : name;
  }

  String get recipientText {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? email : '$name <$email>';
  }
}
