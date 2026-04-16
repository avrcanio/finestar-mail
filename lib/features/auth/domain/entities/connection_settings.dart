enum MailSecurity { none, sslTls, startTls }

class ConnectionSettings {
  const ConnectionSettings({
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
  });

  final String imapHost;
  final int imapPort;
  final MailSecurity imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final MailSecurity smtpSecurity;

  Map<String, dynamic> toJson() => {
    'imapHost': imapHost,
    'imapPort': imapPort,
    'imapSecurity': imapSecurity.name,
    'smtpHost': smtpHost,
    'smtpPort': smtpPort,
    'smtpSecurity': smtpSecurity.name,
  };

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) {
    return ConnectionSettings(
      imapHost: json['imapHost'] as String,
      imapPort: json['imapPort'] as int,
      imapSecurity: MailSecurity.values.byName(json['imapSecurity'] as String),
      smtpHost: json['smtpHost'] as String,
      smtpPort: json['smtpPort'] as int,
      smtpSecurity: MailSecurity.values.byName(json['smtpSecurity'] as String),
    );
  }
}
