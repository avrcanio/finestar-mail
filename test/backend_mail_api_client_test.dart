import 'dart:convert';

import 'package:finestar_mail/data/remote/backend_mail_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('login posts credentials and parses token identity', () async {
    http.Request? capturedRequest;
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'authenticated': true,
            'account_email': 'app-test-1@finestar.hr',
            'token': 'session-token',
            'folder_count': 5,
          }),
          200,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test/',
    );

    final response = await client.login(
      email: 'app-test-1@finestar.hr',
      password: 'secret',
    );

    expect(capturedRequest?.method, 'POST');
    expect(
      capturedRequest?.url,
      Uri.parse('https://mail.example.test/api/auth/login'),
    );
    expect(jsonDecode(capturedRequest!.body), {
      'email': 'app-test-1@finestar.hr',
      'password': 'secret',
    });
    expect(response.authenticated, isTrue);
    expect(response.accountEmail, 'app-test-1@finestar.hr');
    expect(response.token, 'session-token');
    expect(response.folderCount, 5);
  });

  test('authenticated endpoints send Authorization token header', () async {
    final paths = <String>[];
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Token session-token');
        if (request.url.path == '/api/auth/me') {
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'account_email': 'app-test-1@finestar.hr',
            }),
            200,
          );
        }
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
          expect(request.url.queryParameters['before_uid'], isNull);
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'messages': [],
              'has_more': false,
              'next_before_uid': null,
            }),
            200,
          );
        }
        if (request.url.path == '/api/mail/messages/42') {
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'message': {
                'uid': '42',
                'folder': 'INBOX',
                'subject': 'Hello',
                'sender': 'Sender <sender@example.test>',
                'to': ['app-test-1@finestar.hr'],
                'cc': [],
                'date': '2026-04-16T07:00:00Z',
                'message_id': '<m1@example.test>',
                'flags': ['Seen'],
                'size': 123,
                'text_body': 'Plain body',
                'html_body': '',
                'attachments': [],
              },
            }),
            200,
          );
        }
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
    );

    await client.me(token: 'session-token');
    await client.folders(token: 'session-token');
    await client.messages(token: 'session-token', folder: 'INBOX', limit: 50);
    await client.messageDetail(
      token: 'session-token',
      folder: 'INBOX',
      uid: '42',
    );
    await client.send(
      token: 'session-token',
      request: const BackendSendRequest(
        to: ['client@example.test'],
        cc: [],
        bcc: [],
        subject: 'Status',
        textBody: 'Body',
        htmlBody: '',
        replyTo: null,
        fromDisplayName: 'App Test',
      ),
    );

    expect(paths, [
      'GET /api/auth/me',
      'GET /api/mail/folders',
      'GET /api/mail/messages',
      'GET /api/mail/messages/42',
      'POST /api/mail/send',
    ]);
  });

  test(
    'messages supports before_uid cursor and parses pagination envelope',
    () async {
      final requestedUris = <Uri>[];
      final client = BackendMailApiClient(
        httpClient: MockClient((request) async {
          requestedUris.add(request.url);
          expect(request.headers['Authorization'], 'Token session-token');
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'messages': [
                {
                  'uid': '41',
                  'folder': 'INBOX',
                  'subject': 'Older message',
                  'sender': 'sender@example.test',
                  'to': ['app-test-1@finestar.hr'],
                  'cc': [],
                  'date': '2026-04-16T07:00:00Z',
                  'message_id': '<older@example.test>',
                  'flags': [],
                  'size': 123,
                  'has_attachments': true,
                  'has_visible_attachments': false,
                },
              ],
              'has_more': true,
              'next_before_uid': '40',
            }),
            200,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      );

      final firstPage = await client.messages(
        token: 'session-token',
        folder: 'INBOX',
        limit: 50,
      );
      final olderPage = await client.messages(
        token: 'session-token',
        folder: 'INBOX',
        limit: 50,
        beforeUid: '41',
      );

      expect(requestedUris.first.queryParameters, {
        'folder': 'INBOX',
        'limit': '50',
      });
      expect(requestedUris.last.queryParameters, {
        'folder': 'INBOX',
        'limit': '50',
        'before_uid': '41',
      });
      expect(firstPage.hasMore, isTrue);
      expect(firstPage.nextBeforeUid, '40');
      expect(olderPage.messages.single.uid, '41');
      expect(olderPage.messages.single.hasAttachments, isTrue);
      expect(olderPage.messages.single.hasVisibleAttachments, isFalse);
    },
  );

  test('folders parses hierarchy metadata when present', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'account_email': 'app-test-1@finestar.hr',
            'folders': [
              {
                'name': 'INBOX/Izvodi/HPB',
                'path': 'INBOX/Izvodi/HPB',
                'display_name': 'HPB',
                'parent_path': 'INBOX/Izvodi',
                'depth': 2,
                'delimiter': '/',
                'flags': ['HasNoChildren'],
                'selectable': true,
              },
            ],
          }),
          200,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    final response = await client.folders(token: 'session-token');
    final folder = response.folders.single;

    expect(folder.name, 'INBOX/Izvodi/HPB');
    expect(folder.path, 'INBOX/Izvodi/HPB');
    expect(folder.displayName, 'HPB');
    expect(folder.parentPath, 'INBOX/Izvodi');
    expect(folder.depth, 2);
    expect(folder.selectable, isTrue);
  });

  test('message detail parses attachment metadata', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'account_email': 'app-test-1@finestar.hr',
            'folder': 'INBOX',
            'message': {
              'uid': '42',
              'folder': 'INBOX',
              'subject': 'Attachment',
              'sender': 'sender@example.test',
              'to': ['app-test-1@finestar.hr'],
              'cc': [],
              'date': '2026-04-16T07:00:00Z',
              'message_id': '<m1@example.test>',
              'flags': [],
              'size': 123,
              'has_attachments': true,
              'has_visible_attachments': true,
              'text_body': 'See attachment.',
              'html_body': '',
              'attachments': [
                {
                  'id': 'att_1',
                  'filename': 'invoice.pdf',
                  'content_type': 'application/pdf',
                  'size': 182340,
                  'disposition': 'attachment',
                  'is_inline': false,
                  'content_id': '',
                },
              ],
            },
          }),
          200,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    final detail = await client.messageDetail(
      token: 'session-token',
      folder: 'INBOX',
      uid: '42',
    );

    expect(detail.message.hasAttachments, isTrue);
    expect(detail.message.hasVisibleAttachments, isTrue);
    expect(detail.message.attachments.single.id, 'att_1');
    expect(detail.message.attachments.single.filename, 'invoice.pdf');
    expect(detail.message.attachments.single.contentType, 'application/pdf');
    expect(detail.message.attachments.single.size, 182340);
    expect(detail.message.attachments.single.disposition, 'attachment');
    expect(detail.message.attachments.single.isInline, isFalse);
    expect(detail.message.attachments.single.contentId, '');
  });

  test('message detail parses inline content id metadata', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'account_email': 'app-test-1@finestar.hr',
            'folder': 'INBOX',
            'message': {
              'uid': '42',
              'folder': 'INBOX',
              'subject': 'Inline image',
              'sender': 'sender@example.test',
              'to': ['app-test-1@finestar.hr'],
              'cc': [],
              'date': '2026-04-16T07:00:00Z',
              'message_id': '<m1@example.test>',
              'flags': [],
              'size': 123,
              'has_attachments': true,
              'has_visible_attachments': false,
              'text_body': 'Logo',
              'html_body': '<img src="cid:image001.png@example">',
              'attachments': [
                {
                  'id': 'img_1',
                  'filename': 'image001.png',
                  'content_type': 'image/png',
                  'size': 16,
                  'disposition': 'inline',
                  'is_inline': true,
                  'content_id': 'image001.png@example',
                },
              ],
            },
          }),
          200,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    final detail = await client.messageDetail(
      token: 'session-token',
      folder: 'INBOX',
      uid: '42',
    );

    expect(detail.message.hasVisibleAttachments, isFalse);
    expect(detail.message.attachments.single.isInline, isTrue);
    expect(detail.message.attachments.single.contentId, 'image001.png@example');
  });

  test('attachment download sends auth and returns binary metadata', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Token session-token');
        expect(request.url.path, '/api/mail/messages/42/attachments/att_1');
        expect(request.url.queryParameters['folder'], 'INBOX');
        return http.Response.bytes(
          [104, 105],
          200,
          headers: {
            'content-type': 'text/plain',
            'content-disposition': 'attachment; filename="smoke.txt"',
          },
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    final download = await client.downloadAttachment(
      token: 'session-token',
      folder: 'INBOX',
      uid: '42',
      attachmentId: 'att_1',
    );

    expect(download.bytes, [104, 105]);
    expect(download.filename, 'smoke.txt');
    expect(download.contentType, 'text/plain');
  });

  test('multipart send posts attachment file parts', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/mail/send');
        expect(request.headers['Authorization'], 'Token session-token');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        expect(request.body, contains('name="to"'));
        expect(request.body, contains('client@example.test'));
        expect(request.body, contains('name="attachments"'));
        expect(request.body, contains('filename="smoke.txt"'));
        expect(request.body, contains('hello attachment'));
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
    );

    final response = await client.send(
      token: 'session-token',
      request: const BackendSendRequest(
        to: ['client@example.test'],
        cc: [],
        bcc: [],
        subject: 'Status',
        textBody: 'Body',
        htmlBody: '',
        replyTo: null,
        fromDisplayName: 'App Test',
      ),
      attachments: const [
        BackendSendAttachment(
          filename: 'smoke.txt',
          contentType: 'text/plain',
          bytes: [
            104,
            101,
            108,
            108,
            111,
            32,
            97,
            116,
            116,
            97,
            99,
            104,
            109,
            101,
            110,
            116,
          ],
        ),
      ],
    );

    expect(response.messageId, '<sent@example.test>');
  });

  test(
    'delete endpoints send Authorization and parse success responses',
    () async {
      final requests = <http.Request>[];
      final client = BackendMailApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Token session-token');
          if (request.url.path == '/api/mail/messages/delete') {
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
                    'detail': 'IMAP move failed for UID 41',
                  },
                ],
              }),
              200,
            );
          }

          expect(request.url.path, '/api/mail/messages/42/delete');
          expect(request.url.queryParameters['folder'], 'INBOX');
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
      );

      final batch = await client.deleteMessages(
        token: 'session-token',
        folder: 'INBOX',
        uids: ['42', '41'],
      );
      final single = await client.deleteMessage(
        token: 'session-token',
        folder: 'INBOX',
        uid: '42',
      );

      expect(batch.partial, isTrue);
      expect(batch.movedToTrash, ['42']);
      expect(batch.failed.single.uid, '41');
      expect(single.success, isTrue);
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        ['POST /api/mail/messages/delete', 'POST /api/mail/messages/42/delete'],
      );
    },
  );

  test(
    'restore endpoints send Authorization and parse success responses',
    () async {
      final requests = <http.Request>[];
      final client = BackendMailApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Token session-token');
          if (request.url.path == '/api/mail/messages/restore') {
            expect(jsonDecode(request.body), {
              'folder': 'Trash',
              'uids': ['42', '41'],
              'target_folder': 'INBOX',
            });
            return http.Response(
              jsonEncode({
                'account_email': 'app-test-1@finestar.hr',
                'folder': 'Trash',
                'target_folder': 'INBOX',
                'success': false,
                'partial': true,
                'restored': ['42'],
                'failed': [
                  {
                    'uid': '41',
                    'error': 'restore_failed',
                    'detail': 'IMAP restore failed for UID 41',
                  },
                ],
              }),
              200,
            );
          }

          expect(request.url.path, '/api/mail/messages/42/restore');
          expect(request.url.queryParameters['folder'], 'Trash');
          expect(request.url.queryParameters['target_folder'], 'INBOX');
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'Trash',
              'target_folder': 'INBOX',
              'success': true,
              'partial': false,
              'restored': ['42'],
              'failed': [],
            }),
            200,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      );

      final batch = await client.restoreMessages(
        token: 'session-token',
        folder: 'Trash',
        uids: ['42', '41'],
        targetFolder: 'INBOX',
      );
      final single = await client.restoreMessage(
        token: 'session-token',
        folder: 'Trash',
        uid: '42',
        targetFolder: 'INBOX',
      );

      expect(batch.partial, isTrue);
      expect(batch.restored, ['42']);
      expect(batch.failed.single.uid, '41');
      expect(single.success, isTrue);
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'POST /api/mail/messages/restore',
          'POST /api/mail/messages/42/restore',
        ],
      );
    },
  );

  test('backend errors expose stable user-facing messages', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'mail_auth_failed', 'detail': 'bad creds'}),
          401,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    await expectLater(
      client.me(token: 'bad-token'),
      throwsA(
        isA<BackendMailApiException>().having(
          (error) => error.userMessage,
          'message',
          'Mailbox authentication failed. Check your email and password.',
        ),
      ),
    );
  });

  test(
    'pagination validation errors expose stable user-facing messages',
    () async {
      final client = BackendMailApiClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': 'invalid_before_uid',
              'detail': 'before_uid must be numeric',
            }),
            400,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      );

      await expectLater(
        client.messages(
          token: 'session-token',
          folder: 'INBOX',
          limit: 50,
          beforeUid: 'bad',
        ),
        throwsA(
          isA<BackendMailApiException>().having(
            (error) => error.userMessage,
            'message',
            'The mailbox request was invalid.',
          ),
        ),
      );
    },
  );

  test('delete validation errors expose stable user-facing messages', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'delete_from_trash_not_supported'}),
          400,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    await expectLater(
      client.deleteMessages(
        token: 'session-token',
        folder: 'Trash',
        uids: ['1'],
      ),
      throwsA(
        isA<BackendMailApiException>().having(
          (error) => error.userMessage,
          'message',
          'Messages in Trash cannot be deleted from the app yet.',
        ),
      ),
    );
  });

  test(
    'restore validation errors expose stable user-facing messages',
    () async {
      final client = BackendMailApiClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 'restore_target_is_trash'}),
            400,
          );
        }),
        baseUrlLoader: () async => 'https://mail.example.test',
      );

      await expectLater(
        client.restoreMessages(
          token: 'session-token',
          folder: 'Trash',
          uids: ['1'],
          targetFolder: 'INBOX',
        ),
        throwsA(
          isA<BackendMailApiException>().having(
            (error) => error.userMessage,
            'message',
            'The restore request was invalid.',
          ),
        ),
      );
    },
  );

  test('attachment errors expose stable user-facing messages', () async {
    final client = BackendMailApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'attachment_not_found'}),
          404,
        );
      }),
      baseUrlLoader: () async => 'https://mail.example.test',
    );

    await expectLater(
      client.downloadAttachment(
        token: 'session-token',
        folder: 'INBOX',
        uid: '42',
        attachmentId: 'missing',
      ),
      throwsA(
        isA<BackendMailApiException>().having(
          (error) => error.userMessage,
          'message',
          'Attachment could not be found.',
        ),
      ),
    );
  });
}
