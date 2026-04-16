import 'package:enough_mail/imap.dart';
import 'package:enough_mail/smtp.dart';
import 'package:logger/logger.dart';

import '../../core/result/result.dart';
import '../../features/auth/domain/entities/connection_settings.dart';

class MailConnectionTester {
  MailConnectionTester(this._logger);

  final Logger _logger;

  Future<Result<void>> test({
    required String email,
    required String password,
    required ConnectionSettings settings,
  }) async {
    final hasRequiredFields =
        email.isNotEmpty &&
        password.isNotEmpty &&
        settings.imapHost.isNotEmpty &&
        settings.smtpHost.isNotEmpty &&
        settings.imapPort > 0 &&
        settings.smtpPort > 0;

    if (!hasRequiredFields) {
      return const Failure<void>('Missing IMAP/SMTP settings.');
    }

    final imapClient = ImapClient(isLogEnabled: false);
    final smtpClient = SmtpClient('finestar_mail', isLogEnabled: false);

    try {
      await imapClient.connectToServer(
        settings.imapHost,
        settings.imapPort,
        isSecure: settings.imapSecurity == MailSecurity.sslTls,
        timeout: const Duration(seconds: 12),
      );
      if (settings.imapSecurity == MailSecurity.startTls) {
        await imapClient.startTls();
      }
      await imapClient.login(email, password);

      await smtpClient.connectToServer(
        settings.smtpHost,
        settings.smtpPort,
        isSecure: settings.smtpSecurity == MailSecurity.sslTls,
        timeout: const Duration(seconds: 12),
      );
      await smtpClient.ehlo();
      if (settings.smtpSecurity == MailSecurity.startTls) {
        await smtpClient.startTls();
      }
      await smtpClient.authenticate(email, password, AuthMechanism.plain);

      _logger.i(
        'Verified IMAP/SMTP credentials for $email on ${settings.imapHost}.',
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      _logger.w(
        'Mail connection test failed for $email',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>('Unable to verify mailbox credentials: $error');
    } finally {
      await imapClient.disconnect();
      await smtpClient.disconnect();
    }
  }
}
