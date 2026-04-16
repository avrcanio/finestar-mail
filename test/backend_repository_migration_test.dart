import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
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
              expect(request.url.queryParameters['before_uid'], isNull);
              return http.Response(
                jsonEncode({
                  'account_email': 'app-test-1@finestar.hr',
                  'folder': 'INBOX',
                  'has_more': true,
                  'next_before_uid': '42',
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

      final page = await repository.getMessagePage(
        accountId: 'app-test-1@finestar.hr',
        folder: folders.single,
        forceRefresh: true,
      );
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeUid, '42');

      final detail = await repository.getMessageDetail(
        accountId: 'app-test-1@finestar.hr',
        id: summaries.single.id,
      );
      expect(detail.bodyPlain, 'Plain backend body');
    },
  );

  test('mailbox repository requests and appends older backend page', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final storage = _MemorySecureStorageService();
    addTearDown(database.close);
    await storage.saveAuthToken(
      accountId: 'app-test-1@finestar.hr',
      token: 'backend-token',
    );

    final requestedCursors = <String?>[];
    const folder = MailFolder(
      id: 'app-test-1@finestar.hr:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    final inbox = db.MailFoldersCompanion.insert(
      id: 'app-test-1@finestar.hr:inbox',
      accountId: 'app-test-1@finestar.hr',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    await database.into(database.mailFolders).insert(inbox);

    final repository = MailboxRepositoryImpl(
      appDatabase: database,
      secureStorageService: storage,
      backendMailApiClient: BackendMailApiClient(
        httpClient: MockClient((request) async {
          requestedCursors.add(request.url.queryParameters['before_uid']);
          final isOlderPage = request.url.queryParameters['before_uid'] == '42';
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'has_more': !isOlderPage,
              'next_before_uid': isOlderPage ? null : '42',
              'messages': [
                {
                  'uid': isOlderPage ? '41' : '42',
                  'folder': 'INBOX',
                  'subject': isOlderPage ? 'Older backend' : 'Newest backend',
                  'sender': 'sender@example.test',
                  'to': ['app-test-1@finestar.hr'],
                  'cc': [],
                  'date': isOlderPage
                      ? '2026-04-16T06:00:00Z'
                      : '2026-04-16T07:00:00Z',
                  'message_id': isOlderPage
                      ? '<older@example.test>'
                      : '<newest@example.test>',
                  'flags': [],
                  'size': 123,
                },
              ],
            }),
            200,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      ),
    );

    final firstPage = await repository.getMessagePage(
      accountId: 'app-test-1@finestar.hr',
      folder: folder,
      forceRefresh: true,
    );
    final olderPage = await repository.getMessagePage(
      accountId: 'app-test-1@finestar.hr',
      folder: folder,
      beforeUid: firstPage.nextBeforeUid,
    );

    expect(requestedCursors, [null, '42']);
    expect(firstPage.messages.single.id, 'app-test-1@finestar.hr:inbox:api:42');
    expect(olderPage.messages.single.id, 'app-test-1@finestar.hr:inbox:api:41');
    final cached = await database.select(database.messageSummaries).get();
    expect(
      cached.map((row) => row.id),
      containsAll([
        'app-test-1@finestar.hr:inbox:api:42',
        'app-test-1@finestar.hr:inbox:api:41',
      ]),
    );
  });

  test(
    'mailbox repository moves backend messages to trash and removes cache rows',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);
      await storage.saveAuthToken(
        accountId: 'app-test-1@finestar.hr',
        token: 'backend-token',
      );
      const folder = MailFolder(
        id: 'app-test-1@finestar.hr:inbox',
        name: 'INBOX',
        path: 'INBOX',
        isInbox: true,
      );
      await _insertFolder(database, folder);
      await _insertCachedBackendMessage(database, uid: '42');
      await _insertCachedBackendMessage(database, uid: '41');

      final repository = MailboxRepositoryImpl(
        appDatabase: database,
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/mail/messages/delete');
            expect(request.headers['Authorization'], 'Token backend-token');
            expect(jsonDecode(request.body), {
              'folder': 'INBOX',
              'uids': ['42', '41'],
            });
            return http.Response(
              jsonEncode({
                'account_email': 'app-test-1@finestar.hr',
                'folder': 'INBOX',
                'trash_folder': 'Trash',
                'success': false,
                'partial': true,
                'moved_to_trash': ['42'],
                'failed': [
                  {
                    'uid': '41',
                    'error': 'move_failed',
                    'detail': 'Unable to move UID 41',
                  },
                ],
              }),
              200,
            );
          }),
          baseUrlLoader: () async => 'https://mail.example.test',
        ),
      );

      final result = await repository.moveMessagesToTrash(
        accountId: 'app-test-1@finestar.hr',
        folder: folder,
        messageIds: [
          'app-test-1@finestar.hr:inbox:api:42',
          'app-test-1@finestar.hr:inbox:api:41',
        ],
      );

      expect(result.movedMessageIds, ['app-test-1@finestar.hr:inbox:api:42']);
      expect(
        result.failed.single.messageId,
        'app-test-1@finestar.hr:inbox:api:41',
      );
      expect(
        await _cachedSummary(database, 'app-test-1@finestar.hr:inbox:api:42'),
        isNull,
      );
      expect(
        await _cachedDetail(database, 'app-test-1@finestar.hr:inbox:api:42'),
        isNull,
      );
      expect(
        await _cachedSummary(database, 'app-test-1@finestar.hr:inbox:api:41'),
        isNotNull,
      );
    },
  );

  test('mailbox repository single delete derives folder and uid', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    final storage = _MemorySecureStorageService();
    addTearDown(database.close);
    await storage.saveAuthToken(
      accountId: 'app-test-1@finestar.hr',
      token: 'backend-token',
    );
    const folder = MailFolder(
      id: 'app-test-1@finestar.hr:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    await _insertFolder(database, folder);
    await _insertCachedBackendMessage(database, uid: '42');

    final repository = MailboxRepositoryImpl(
      appDatabase: database,
      secureStorageService: storage,
      backendMailApiClient: BackendMailApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/mail/messages/42/delete');
          expect(request.url.queryParameters['folder'], 'INBOX');
          expect(request.headers['Authorization'], 'Token backend-token');
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'trash_folder': 'Trash',
              'success': true,
              'partial': false,
              'moved_to_trash': ['42'],
              'failed': [],
            }),
            200,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      ),
    );

    final result = await repository.moveMessageToTrash(
      accountId: 'app-test-1@finestar.hr',
      messageId: 'app-test-1@finestar.hr:inbox:api:42',
    );

    expect(result.movedMessageIds, ['app-test-1@finestar.hr:inbox:api:42']);
    expect(
      await _cachedSummary(database, 'app-test-1@finestar.hr:inbox:api:42'),
      isNull,
    );
  });

  test(
    'mailbox repository rejects local-only trash moves without http',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);
      var httpCalls = 0;
      const folder = MailFolder(
        id: 'app-test-1@finestar.hr:inbox',
        name: 'INBOX',
        path: 'INBOX',
        isInbox: true,
      );

      final repository = MailboxRepositoryImpl(
        appDatabase: database,
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            httpCalls++;
            return http.Response('{}', 500);
          }),
          baseUrlLoader: () async => 'https://mail.example.test',
        ),
      );

      final result = await repository.moveMessagesToTrash(
        accountId: 'app-test-1@finestar.hr',
        folder: folder,
        messageIds: ['app-test-1@finestar.hr:inbox:local:42'],
      );

      expect(result.movedMessageIds, isEmpty);
      expect(
        result.failed.single.messageId,
        'app-test-1@finestar.hr:inbox:local:42',
      );
      expect(httpCalls, 0);
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

  test(
    'compose repository normalizes display-name recipients before send and sent cache',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);
      await _insertAccountAndToken(database, storage);

      final repository = ComposeRepositoryImpl(
        appDatabase: database,
        logger: Logger(printer: SimplePrinter(printTime: false)),
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/mail/send');
            expect(jsonDecode(request.body), {
              'to': ['client@example.test'],
              'cc': ['copy@example.test'],
              'bcc': ['hidden@example.test'],
              'subject': 'Display recipient send',
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
          to: ['Client Name <client@example.test>'],
          cc: ['Copy Name <copy@example.test>'],
          bcc: ['Hidden Name <hidden@example.test>'],
          subject: 'Display recipient send',
          body: 'Hello from backend.',
          attachments: [],
        ),
      );

      expect(result, isA<Success<void>>());
      final details = await database.select(database.messageDetails).get();
      expect(
        details.single.recipients,
        'client@example.test,copy@example.test,hidden@example.test',
      );
    },
  );

  test(
    'compose repository rejects malformed and packed recipients before http',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      final storage = _MemorySecureStorageService();
      addTearDown(database.close);
      var httpCalls = 0;

      final repository = ComposeRepositoryImpl(
        appDatabase: database,
        logger: Logger(printer: SimplePrinter(printTime: false)),
        secureStorageService: storage,
        backendMailApiClient: BackendMailApiClient(
          httpClient: MockClient((request) async {
            httpCalls++;
            return http.Response('{}', 500);
          }),
          baseUrlLoader: () async => 'https://mail.example.test',
        ),
      );

      for (final recipient in [
        '',
        'Client Name <not-an-email>',
        'client@example.test, other@example.test',
        'Client Name <client@example.test> trailing',
      ]) {
        final result = await repository.send(
          OutgoingMessage(
            accountId: 'app-test-1@finestar.hr',
            to: [recipient],
            cc: const [],
            bcc: const [],
            subject: 'Invalid recipient send',
            body: 'Hello from backend.',
            attachments: const [],
          ),
        );

        expect(
          result,
          isA<Failure<void>>().having(
            (failure) => failure.message,
            'message',
            'Recipient addresses must be valid email addresses.',
          ),
        );
        expect(httpCalls, 0);
      }
    },
  );
}

Future<void> _insertFolder(db.AppDatabase database, MailFolder folder) async {
  await database
      .into(database.mailFolders)
      .insert(
        db.MailFoldersCompanion.insert(
          id: folder.id,
          accountId: 'app-test-1@finestar.hr',
          name: folder.name,
          path: folder.path,
          isInbox: folder.isInbox,
        ),
      );
}

Future<void> _insertCachedBackendMessage(
  db.AppDatabase database, {
  required String uid,
}) async {
  final id = 'app-test-1@finestar.hr:inbox:api:$uid';
  final receivedAt = DateTime.utc(2026, 4, 16, 7, int.parse(uid) % 60);
  await database
      .into(database.messageSummaries)
      .insert(
        db.MessageSummariesCompanion.insert(
          id: id,
          accountId: const Value('app-test-1@finestar.hr'),
          folderId: 'app-test-1@finestar.hr:inbox',
          subject: 'Backend message $uid',
          sender: 'sender@example.test',
          preview: 'Preview $uid',
          receivedAt: receivedAt,
          isRead: false,
          hasAttachments: false,
          sequence: int.parse(uid),
        ),
      );
  await database
      .into(database.messageDetails)
      .insert(
        db.MessageDetailsCompanion.insert(
          id: id,
          accountId: const Value('app-test-1@finestar.hr'),
          folderId: const Value('app-test-1@finestar.hr:inbox'),
          subject: 'Backend message $uid',
          sender: 'sender@example.test',
          recipients: 'app-test-1@finestar.hr',
          bodyPlain: 'Body $uid',
          receivedAt: receivedAt,
          messageIdHeader: Value('<$uid@example.test>'),
        ),
      );
}

Future<db.MessageSummary?> _cachedSummary(db.AppDatabase database, String id) {
  return (database.select(
    database.messageSummaries,
  )..where((table) => table.id.equals(id))).getSingleOrNull();
}

Future<db.MessageDetail?> _cachedDetail(db.AppDatabase database, String id) {
  return (database.select(
    database.messageDetails,
  )..where((table) => table.id.equals(id))).getSingleOrNull();
}

Future<void> _insertAccountAndToken(
  db.AppDatabase database,
  _MemorySecureStorageService storage,
) async {
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
