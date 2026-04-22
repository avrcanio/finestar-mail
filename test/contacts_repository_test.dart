import 'dart:convert';

import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/data/remote/backend_mail_api_client.dart';
import 'package:finestar_mail/data/secure/secure_storage_service.dart';
import 'package:finestar_mail/features/auth/data/backend_auth_token_selector.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/domain/repositories/auth_repository.dart';
import 'package:finestar_mail/features/contacts/data/contacts_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'suggestContacts skips backend before three trimmed characters',
    () async {
      var requestCount = 0;
      final repository = _buildRepository(
        storage: _MemorySecureStorageService(activeAccountId: _account.id)
          ..tokens[_account.id] = 'session-token',
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response(jsonEncode({'contacts': []}), 200);
        }),
      );

      final suggestions = await repository.suggestContacts(' ab ');

      expect(suggestions, isEmpty);
      expect(requestCount, 0);
    },
  );

  test(
    'suggestContacts fetches suggestions with active account token',
    () async {
      http.Request? capturedRequest;
      final repository = _buildRepository(
        storage: _MemorySecureStorageService(activeAccountId: _account.id)
          ..tokens[_account.id] = 'session-token',
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'contacts': [
                {
                  'id': 7,
                  'email': 'client@example.test',
                  'display_name': 'Client Name',
                  'source': 'manual',
                  'times_contacted': 3,
                  'last_used_at': '2026-04-22T20:30:00Z',
                  'created_at': '2026-04-20T08:00:00Z',
                  'updated_at': '2026-04-22T20:30:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );

      final suggestions = await repository.suggestContacts(' cli ');

      expect(capturedRequest?.url.path, '/api/contacts/suggest');
      expect(capturedRequest?.url.queryParameters['q'], 'cli');
      expect(capturedRequest?.headers['Authorization'], 'Token session-token');
      expect(suggestions.single.displayLabel, 'Client Name');
      expect(
        suggestions.single.recipientText,
        'Client Name <client@example.test>',
      );
    },
  );

  test('suggestContacts returns empty when account token is missing', () async {
    var requestCount = 0;
    final repository = _buildRepository(
      storage: _MemorySecureStorageService(activeAccountId: _account.id),
      httpClient: MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({'contacts': []}), 200);
      }),
    );

    final suggestions = await repository.suggestContacts('client');

    expect(suggestions, isEmpty);
    expect(requestCount, 0);
  });

  test('suggestContacts returns empty when backend request fails', () async {
    final repository = _buildRepository(
      storage: _MemorySecureStorageService(activeAccountId: _account.id)
        ..tokens[_account.id] = 'session-token',
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'not_authenticated'}), 401);
      }),
    );

    final suggestions = await repository.suggestContacts('client');

    expect(suggestions, isEmpty);
  });
}

ContactsRepositoryImpl _buildRepository({
  required _MemorySecureStorageService storage,
  required http.Client httpClient,
}) {
  return ContactsRepositoryImpl(
    backendMailApiClient: BackendMailApiClient(
      httpClient: httpClient,
      baseUrlLoader: () async => 'https://mail.example.test',
    ),
    backendAuthTokenSelector: BackendAuthTokenSelector(
      authRepository: _FakeAuthRepository([_account]),
      secureStorageService: storage,
    ),
  );
}

const _settings = ConnectionSettings(
  imapHost: 'mail.finestar.hr',
  imapPort: 993,
  imapSecurity: MailSecurity.sslTls,
  smtpHost: 'mail.finestar.hr',
  smtpPort: 465,
  smtpSecurity: MailSecurity.sslTls,
);

final _account = MailAccount(
  id: 'app-test-1@finestar.hr',
  email: 'app-test-1@finestar.hr',
  displayName: 'App Test',
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
