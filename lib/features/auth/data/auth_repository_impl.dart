import '../../../core/result/result.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/mail_connection_tester.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/connection_settings.dart';
import '../domain/entities/mail_account.dart';
import '../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SecureStorageService secureStorageService,
    required MailConnectionTester mailConnectionTester,
    required AppDatabase appDatabase,
  }) : _secureStorageService = secureStorageService,
       _mailConnectionTester = mailConnectionTester,
       _appDatabase = appDatabase;

  final SecureStorageService _secureStorageService;
  final MailConnectionTester _mailConnectionTester;
  final AppDatabase _appDatabase;

  @override
  Future<MailAccount?> getSignedInAccount() async {
    final json = await _secureStorageService.readAccount();
    if (json == null) {
      return null;
    }
    return MailAccount.fromJson(json);
  }

  @override
  Future<Result<MailAccount>> signIn({
    required String email,
    required String displayName,
    required String password,
    required ConnectionSettings settings,
  }) async {
    final connectionResult = await testConnection(
      email: email,
      password: password,
      settings: settings,
    );

    if (connectionResult.isFailure) {
      return connectionResult.when(
        success: (_) => const Failure<MailAccount>('Unexpected sign-in state.'),
        failure: Failure.new,
      );
    }

    final account = MailAccount(
      id: email.toLowerCase(),
      email: email,
      displayName: displayName.isEmpty ? email : displayName,
      connectionSettings: settings,
      createdAt: DateTime.now(),
    );

    await _secureStorageService.saveAccount(
      accountJson: account.toJson(),
      password: password,
    );

    await _appDatabase
        .into(_appDatabase.accounts)
        .insertOnConflictUpdate(
          AccountsCompanion.insert(
            id: account.id,
            email: account.email,
            displayName: account.displayName,
            imapHost: settings.imapHost,
            imapPort: settings.imapPort,
            imapSecurity: settings.imapSecurity.name,
            smtpHost: settings.smtpHost,
            smtpPort: settings.smtpPort,
            smtpSecurity: settings.smtpSecurity.name,
            createdAt: account.createdAt,
          ),
        );

    return Success(account);
  }

  @override
  Future<void> signOut() => _secureStorageService.clear();

  @override
  Future<Result<void>> testConnection({
    required String email,
    required String password,
    required ConnectionSettings settings,
  }) {
    return _mailConnectionTester.test(
      email: email,
      password: password,
      settings: settings,
    );
  }
}
