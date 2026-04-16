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
  Future<List<MailAccount>> getAccounts() async {
    await _migrateLegacyAccountIfPresent();
    final rows = await _appDatabase.select(_appDatabase.accounts).get();
    return rows.map(_accountFromRow).toList();
  }

  @override
  Future<MailAccount?> getActiveAccount() async {
    final accounts = await getAccounts();
    if (accounts.isEmpty) {
      await _secureStorageService.clearActiveAccountId();
      return null;
    }

    final activeAccountId = await _secureStorageService.readActiveAccountId();
    MailAccount? activeAccount;
    for (final account in accounts) {
      if (account.id == activeAccountId) {
        activeAccount = account;
        break;
      }
    }

    if (activeAccount != null) {
      return activeAccount;
    }

    final fallback = accounts.first;
    await setActiveAccount(fallback.id);
    return fallback;
  }

  @override
  Future<void> setActiveAccount(String accountId) async {
    final exists = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(accountId))).getSingleOrNull();

    if (exists != null) {
      await _secureStorageService.saveActiveAccountId(accountId);
    }
  }

  @override
  Future<Result<MailAccount>> addAccount({
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

    await _secureStorageService.savePassword(
      accountId: account.id,
      password: password,
    );

    final accounts = await getAccounts();
    if (accounts.length == 1) {
      await setActiveAccount(account.id);
    }

    return Success(account);
  }

  @override
  Future<void> removeAccount(String accountId) async {
    await (_appDatabase.delete(
      _appDatabase.attachmentMetadata,
    )..where((table) => table.accountId.equals(accountId))).go();
    await (_appDatabase.delete(
      _appDatabase.messageDetails,
    )..where((table) => table.accountId.equals(accountId))).go();
    await (_appDatabase.delete(
      _appDatabase.messageSummaries,
    )..where((table) => table.accountId.equals(accountId))).go();
    await (_appDatabase.delete(
      _appDatabase.mailFolders,
    )..where((table) => table.accountId.equals(accountId))).go();
    await (_appDatabase.delete(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(accountId))).go();

    await _secureStorageService.deletePassword(accountId);

    final activeAccountId = await _secureStorageService.readActiveAccountId();
    if (activeAccountId == accountId) {
      final remaining = await getAccounts();
      if (remaining.isEmpty) {
        await _secureStorageService.clearActiveAccountId();
      } else {
        await setActiveAccount(remaining.first.id);
      }
    }
  }

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

  Future<void> _migrateLegacyAccountIfPresent() {
    return _secureStorageService.migrateLegacyAccountIfPresent(
      saveAccount: (json) async {
        final account = MailAccount.fromJson(json);
        await _appDatabase
            .into(_appDatabase.accounts)
            .insertOnConflictUpdate(
              AccountsCompanion.insert(
                id: account.id,
                email: account.email,
                displayName: account.displayName,
                imapHost: account.connectionSettings.imapHost,
                imapPort: account.connectionSettings.imapPort,
                imapSecurity: account.connectionSettings.imapSecurity.name,
                smtpHost: account.connectionSettings.smtpHost,
                smtpPort: account.connectionSettings.smtpPort,
                smtpSecurity: account.connectionSettings.smtpSecurity.name,
                createdAt: account.createdAt,
              ),
            );
      },
    );
  }

  MailAccount _accountFromRow(Account row) {
    return MailAccount(
      id: row.id,
      email: row.email,
      displayName: row.displayName,
      connectionSettings: ConnectionSettings(
        imapHost: row.imapHost,
        imapPort: row.imapPort,
        imapSecurity: MailSecurity.values.byName(row.imapSecurity),
        smtpHost: row.smtpHost,
        smtpPort: row.smtpPort,
        smtpSecurity: MailSecurity.values.byName(row.smtpSecurity),
      ),
      createdAt: row.createdAt,
    );
  }
}
