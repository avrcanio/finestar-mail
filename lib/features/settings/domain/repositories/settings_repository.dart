import '../../../auth/domain/entities/mail_account.dart';

abstract class SettingsRepository {
  Future<MailAccount?> getAccount();
}
