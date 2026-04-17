import '../../../../core/result/result.dart';
import '../entities/mail_account.dart';

abstract class AuthRepository {
  Future<List<MailAccount>> getAccounts();

  Future<MailAccount?> getActiveAccount();

  Future<void> setActiveAccount(String accountId);

  Future<Result<MailAccount>> addAccount({
    required String email,
    required String displayName,
    required String password,
  });

  Future<void> removeAccount(String accountId);
}
