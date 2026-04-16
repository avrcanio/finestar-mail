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
          return http.Response(
            jsonEncode({
              'account_email': 'app-test-1@finestar.hr',
              'folder': 'INBOX',
              'messages': [],
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
}
