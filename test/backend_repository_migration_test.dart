import 'dart:convert';

import 'package:drift/native.dart';
import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/data/local/app_database.dart' as db;
import 'package:finestar_mail/data/remote/backend_mail_api_client.dart';
import 'package:finestar_mail/data/secure/secure_storage_service.dart';
import 'package:finestar_mail/features/auth/data/auth_repository_impl.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/compose/data/compose_repository_impl.dart';
import 'package:finestar_mail/features/compose/domain/entities/outgoing_message.dart';
import 'package:finestar_mail/features/mailbox/data/mailbox_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';

void main() {
  test('auth repository logs in through backend and stores token', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final storage = _MemorySecureStorageService();
    addTearDown(database.close);

    final repository = AuthRepositoryImpl(
      secureStorageService: storage,
      backendMailApiClient: BackendMailApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/auth/login');
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'account_email': 'app-test-1@finestar.hr',
              'token': 'backend-token',
            }),
            200,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      ),
      appDatabase: database,
    );

    final result = await repository.addAccount(
      email: 'APP-TEST-1@finestar.hr',
      displayName: 'App Test',
      password: 'secret',
      settings: _settings,
    );

    expect(result, isA<Success>());
    expect(
      await storage.readAuthToken('app-test-1@finestar.hr'),
      'backend-token',
    );
    expect(await storage.readPassword('app-test-1@finestar.hr'), isNull);
    final account = await (database.select(
      database.accounts,
    )..where((table) => table.id.equals('app-test-1@finestar.hr'))).getSingle();
    expect(account.email, 'app-test-1@finestar.hr');
  });

  test(
    'mailbox repository maps backend folders, summaries, and detail',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);
      await storage.saveAuthToken(
        accountId: 'app-test-1@finestar.hr',
        token: 'backend-token',
      );

      final repository = MailboxRepositoryImpl(
        appDatabase: database,
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            expect(request.headers['Authorization'], 'Token backend-token');
            if (request.url.path == '/api/mail/folders') {
              return http.Response(
                jsonEncode({
                  'account_email': 'app-test-1@finestar.hr',
                  'folders': [
                    {'name': 'INBOX', 'delimiter': '/', 'flags': []},
                  ],
                }),
                200,
              );
            }
            if (request.url.path == '/api/mail/messages') {
              expect(request.url.queryParameters['folder'], 'INBOX');
              return http.Response(
                jsonEncode({
                  'account_email': 'app-test-1@finestar.hr',
                  'folder': 'INBOX',
                  'messages': [
                    {
                      'uid': '42',
                      'folder': 'INBOX',
                      'subject': 'Backend hello',
                      'sender': 'Sender <sender@example.test>',
                      'to': ['app-test-1@finestar.hr'],
                      'cc': [],
                      'date': '2026-04-16T07:00:00Z',
                      'message_id': '<m1@example.test>',
                      'flags': ['Seen'],
                      'size': 123,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'account_email': 'app-test-1@finestar.hr',
                'folder': 'INBOX',
                'message': {
                  'uid': '42',
                  'folder': 'INBOX',
                  'subject': 'Backend hello',
                  'sender': 'Sender <sender@example.test>',
                  'to': ['app-test-1@finestar.hr'],
                  'cc': [],
                  'date': '2026-04-16T07:00:00Z',
                  'message_id': '<m1@example.test>',
                  'flags': ['Seen'],
                  'size': 123,
                  'text_body': 'Plain backend body',
                  'html_body': '<p>Plain backend body</p>',
                  'attachments': [],
                },
              }),
              200,
            );
          }),
          baseUrlLoader: () async => 'https://mail.example.test',
        ),
      );

      final folders = await repository.getFolders('app-test-1@finestar.hr');
      expect(folders.single.id, 'app-test-1@finestar.hr:inbox');

      final summaries = await repository.getMessages(
        accountId: 'app-test-1@finestar.hr',
        folder: folders.single,
        forceRefresh: true,
      );
      expect(summaries.single.id, 'app-test-1@finestar.hr:inbox:api:42');
      expect(summaries.single.isRead, isTrue);

      final detail = await repository.getMessageDetail(
        accountId: 'app-test-1@finestar.hr',
        id: summaries.single.id,
      );
      expect(detail.bodyPlain, 'Plain backend body');
    },
  );

  test(
    'compose repository posts backend send payload and caches sent mail',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);

      await database
          .into(database.accounts)
          .insert(
            db.AccountsCompanion.insert(
              id: 'app-test-1@finestar.hr',
              email: 'app-test-1@finestar.hr',
              displayName: 'App Test',
              imapHost: _settings.imapHost,
              imapPort: _settings.imapPort,
              imapSecurity: _settings.imapSecurity.name,
              smtpHost: _settings.smtpHost,
              smtpPort: _settings.smtpPort,
              smtpSecurity: _settings.smtpSecurity.name,
              createdAt: DateTime(2026, 4, 16),
            ),
          );
      await storage.saveAuthToken(
        accountId: 'app-test-1@finestar.hr',
        token: 'backend-token',
      );

      final repository = ComposeRepositoryImpl(
        appDatabase: database,
        logger: Logger(printer: SimplePrinter(printTime: false)),
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/mail/send');
            expect(request.headers['Authorization'], 'Token backend-token');
            expect(jsonDecode(request.body), {
              'to': ['client@example.test'],
              'cc': <String>[],
              'bcc': <String>[],
              'subject': 'Backend send',
              'text_body': 'Hello from backend.',
              'html_body': '',
              'reply_to': null,
              'from_display_name': 'App Test',
            });
            return http.Response(
              jsonEncode({
                'account_email': 'app-test-1@finestar.hr',
                'status': 'sent',
                'message_id': '<sent@example.test>',
              }),
              200,
            );
          }),
          baseUrlLoader: () async => 'https://mail.example.test',
        ),
      );

      final result = await repository.send(
        const OutgoingMessage(
          accountId: 'app-test-1@finestar.hr',
          to: ['client@example.test'],
          cc: [],
          bcc: [],
          subject: 'Backend send',
          body: 'Hello from backend.',
          attachments: [],
        ),
      );

      expect(result, isA<Success>());
      final details = await database.select(database.messageDetails).get();
      expect(details.single.messageIdHeader, '<sent@example.test>');
      expect(details.single.bodyPlain, 'Hello from backend.');
    },
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

class _MemorySecureStorageService extends SecureStorageService {
  final _active = <String, String>{};
  final _passwords = <String, String>{};
  final _tokens = <String, String>{};

  @override
  Future<void> saveActiveAccountId(String accountId) async {
    _active['id'] = accountId;
  }

  @override
  Future<String?> readActiveAccountId() async => _active['id'];

  @override
  Future<void> savePassword({
    required String accountId,
    required String password,
  }) async {
    _passwords[accountId] = password;
  }

  @override
  Future<String?> readPassword(String accountId) async => _passwords[accountId];

  @override
  Future<void> deletePassword(String accountId) async {
    _passwords.remove(accountId);
  }

  @override
  Future<void> saveAuthToken({
    required String accountId,
    required String token,
  }) async {
    _tokens[accountId] = token;
  }

  @override
  Future<String?> readAuthToken(String accountId) async => _tokens[accountId];

  @override
  Future<void> deleteAuthToken(String accountId) async {
    _tokens.remove(accountId);
  }

  @override
  Future<void> clearActiveAccountId() async {
    _active.remove('id');
  }

  @override
  Future<void> migrateLegacyAccountIfPresent({
    required Future<void> Function(Map<String, dynamic> accountJson)
    saveAccount,
  }) async {}
}
