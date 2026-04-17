import '../../../core/result/result.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/backend_mail_api_client.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/connection_settings.dart';
import '../domain/entities/mail_account.dart';
import '../domain/repositories/auth_repository.dart';

const _legacyConnectionSettings = ConnectionSettings(
  imapHost: '',
  imapPort: 0,
  imapSecurity: MailSecurity.none,
  smtpHost: '',
  smtpPort: 0,
  smtpSecurity: MailSecurity.none,
);

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required SecureStorageService secureStorageService,
    required BackendMailApiClient backendMailApiClient,
    required AppDatabase appDatabase,
  }) : _secureStorageService = secureStorageService,
       _backendMailApiClient = backendMailApiClient,
       _appDatabase = appDatabase;

  final SecureStorageService _secureStorageService;
  final BackendMailApiClient _backendMailApiClient;
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

    if (activeAccount != null && await _hasValidBackendSession(activeAccount)) {
      return activeAccount;
    }

    final fallback = accounts.first;
    if (await _hasValidBackendSession(fallback)) {
      await setActiveAccount(fallback.id);
      return fallback;
    }

    await _secureStorageService.clearActiveAccountId();
    return null;
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
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    BackendLoginResponse loginResponse;
    try {
      loginResponse = await _backendMailApiClient.login(
        email: normalizedEmail,
        password: password,
      );
    } on BackendMailApiException catch (error) {
      return Failure<MailAccount>(error.userMessage);
    } catch (error) {
      return Failure<MailAccount>('Unable to sign in: $error');
    }

    if (!loginResponse.authenticated || loginResponse.token.trim().isEmpty) {
      return const Failure<MailAccount>(
        'Backend did not return a valid session token.',
      );
    }

    final account = MailAccount(
      id: normalizedEmail,
      email: loginResponse.accountEmail.isEmpty
          ? normalizedEmail
          : loginResponse.accountEmail,
      displayName: displayName.isEmpty ? email : displayName,
      connectionSettings: _legacyConnectionSettings,
      createdAt: DateTime.now(),
    );

    await _appDatabase
        .into(_appDatabase.accounts)
        .insertOnConflictUpdate(
          AccountsCompanion.insert(
            id: account.id,
            email: account.email,
            displayName: account.displayName,
            imapHost: _legacyConnectionSettings.imapHost,
            imapPort: _legacyConnectionSettings.imapPort,
            imapSecurity: _legacyConnectionSettings.imapSecurity.name,
            smtpHost: _legacyConnectionSettings.smtpHost,
            smtpPort: _legacyConnectionSettings.smtpPort,
            smtpSecurity: _legacyConnectionSettings.smtpSecurity.name,
            createdAt: account.createdAt,
          ),
        );

    await _secureStorageService.saveAuthToken(
      accountId: account.id,
      token: loginResponse.token,
    );
    await _secureStorageService.deletePassword(account.id);

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
    await _secureStorageService.deleteAuthToken(accountId);

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

  Future<bool> _hasValidBackendSession(MailAccount account) async {
    final token = await _secureStorageService.readAuthToken(account.id);
    if (token == null || token.trim().isEmpty) {
      return false;
    }
    try {
      final identity = await _backendMailApiClient.me(token: token);
      return identity.authenticated &&
          identity.accountEmail.toLowerCase() == account.email.toLowerCase();
    } on BackendMailApiException catch (error) {
      if (error.isUnauthorized) {
        await _secureStorageService.deleteAuthToken(account.id);
      }
      return false;
    } catch (_) {
      return false;
    }
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
