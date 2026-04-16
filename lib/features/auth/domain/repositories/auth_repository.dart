import '../../../../core/result/result.dart';
import '../entities/connection_settings.dart';
import '../entities/mail_account.dart';

abstract class AuthRepository {
  Future<MailAccount?> getSignedInAccount();

  Future<Result<void>> testConnection({
    required String email,
    required String password,
    required ConnectionSettings settings,
  });

  Future<Result<MailAccount>> signIn({
    required String email,
    required String displayName,
    required String password,
    required ConnectionSettings settings,
  });

  Future<void> signOut();
}
