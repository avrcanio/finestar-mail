import 'connection_settings.dart';

class MailAccount {
  const MailAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.connectionSettings,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final ConnectionSettings connectionSettings;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'connectionSettings': connectionSettings.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      connectionSettings: ConnectionSettings.fromJson(
        json['connectionSettings'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
