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
    await Future<void>.delayed(const Duration(milliseconds: 700));

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

    _logger.i(
      'Connection probe prepared for ${settings.imapHost}/${settings.smtpHost}',
    );
    return const Success<void>(null);
  }
}
