import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/finestar_mailer_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Finestar mailer preset uses canonical docker mailserver settings', () {
    const settings = FinestarMailerPreset.settings;

    expect(settings.imapHost, 'mail.finestar.hr');
    expect(settings.imapPort, 993);
    expect(settings.imapSecurity, MailSecurity.sslTls);
    expect(settings.smtpHost, 'mail.finestar.hr');
    expect(settings.smtpPort, 465);
    expect(settings.smtpSecurity, MailSecurity.sslTls);
    expect(FinestarMailerPreset.smtpStartTlsPort, 587);
  });
}
