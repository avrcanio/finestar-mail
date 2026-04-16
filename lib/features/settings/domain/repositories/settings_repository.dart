import '../../../auth/domain/entities/mail_account.dart';

abstract class SettingsRepository {
  Future<List<MailAccount>> getAccounts();

  Future<MailAccount?> getActiveAccount();
}
