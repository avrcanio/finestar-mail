import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/data/secure/secure_storage_service.dart';
import 'package:finestar_mail/features/auth/data/backend_auth_token_selector.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/domain/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selectToken prefers active account token', () async {
    final storage = _MemorySecureStorageService(activeAccountId: _backup.id)
      ..tokens[_primary.id] = 'primary-token'
      ..tokens[_backup.id] = 'backup-token';
    final selector = BackendAuthTokenSelector(
      authRepository: _FakeAuthRepository([_primary, _backup]),
      secureStorageService: storage,
    );

    final selected = await selector.selectToken();

    expect(selected?.account.id, _backup.id);
    expect(selected?.token, 'backup-token');
  });

  test('selectToken falls back to first account with token', () async {
    final storage = _MemorySecureStorageService(activeAccountId: _backup.id)
      ..tokens[_primary.id] = 'primary-token';
    final selector = BackendAuthTokenSelector(
      authRepository: _FakeAuthRepository([_primary, _backup]),
      secureStorageService: storage,
    );

    final selected = await selector.selectToken();

    expect(selected?.account.id, _primary.id);
    expect(selected?.token, 'primary-token');
  });
}

final _settings = const ConnectionSettings(
  imapHost: 'mail.finestar.hr',
  imapPort: 993,
  imapSecurity: MailSecurity.sslTls,
  smtpHost: 'mail.finestar.hr',
  smtpPort: 465,
  smtpSecurity: MailSecurity.sslTls,
);

final _primary = MailAccount(
  id: 'avrcan@finestar.hr',
  email: 'avrcan@finestar.hr',
  displayName: 'Ante Vrcan',
  connectionSettings: _settings,
  createdAt: DateTime(2026, 4, 16),
);

final _backup = MailAccount(
  id: 'backup@finestar.hr',
  email: 'backup@finestar.hr',
  displayName: 'Backup Mailbox',
  connectionSettings: _settings,
  createdAt: DateTime(2026, 4, 16),
);

class _MemorySecureStorageService extends SecureStorageService {
  _MemorySecureStorageService({this.activeAccountId});

  String? activeAccountId;
  final tokens = <String, String>{};

  @override
  Future<String?> readActiveAccountId() async => activeAccountId;

  @override
  Future<String?> readAuthToken(String accountId) async => tokens[accountId];
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository(this.accounts);

  final List<MailAccount> accounts;

  @override
  Future<List<MailAccount>> getAccounts() async => accounts;

  @override
  Future<MailAccount?> getActiveAccount() async => null;

  @override
  Future<void> setActiveAccount(String accountId) async {}

  @override
  Future<Result<MailAccount>> addAccount({
    required String email,
    required String displayName,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> removeAccount(String accountId) async {}
}
