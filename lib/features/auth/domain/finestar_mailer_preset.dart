import 'entities/connection_settings.dart';

class FinestarMailerPreset {
  static const host = 'mail.finestar.hr';
  static const imapPort = 993;
  static const smtpPort = 465;
  static const smtpStartTlsPort = 587;
  static const authMechanisms = ['PLAIN', 'LOGIN'];

  static const settings = ConnectionSettings(
    imapHost: host,
    imapPort: imapPort,
    imapSecurity: MailSecurity.sslTls,
    smtpHost: host,
    smtpPort: smtpPort,
    smtpSecurity: MailSecurity.sslTls,
  );
}
