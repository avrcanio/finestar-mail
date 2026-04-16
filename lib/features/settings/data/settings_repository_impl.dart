import '../../auth/domain/entities/mail_account.dart';
import '../../auth/domain/repositories/auth_repository.dart';
import '../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  @override
  Future<MailAccount?> getAccount() => _authRepository.getSignedInAccount();
}
