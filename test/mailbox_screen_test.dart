import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_thread.dart';
import 'package:finestar_mail/features/mailbox/domain/repositories/mailbox_repository.dart';
import 'package:finestar_mail/features/mailbox/presentation/mailbox_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('mailbox shell shows Gmail-like controls and drawer', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open folders'), findsOneWidget);
    expect(find.text('Search in mail'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();

    expect(find.text('Finestar Mail'), findsNothing);
    expect(find.text('INBOX'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Junk'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('selecting a non-inbox server folder shows synced messages', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();

    expect(find.text('Sent sync smoke'), findsOneWidget);
    expect(find.text('Folder sync coming next.'), findsNothing);
  });

  testWidgets('avatar opens account management route', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Manage your account'), findsOneWidget);
  });
}

Widget _buildTestApp() {
  final router = GoRouter(
    initialLocation: AppRoute.inbox.path,
    routes: [
      GoRoute(
        path: AppRoute.inbox.path,
        builder: (context, state) => const MailboxScreen(),
      ),
      GoRoute(
        path: AppRoute.settings.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Manage your account'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      activeAccountProvider.overrideWith((ref) async => _account),
      mailboxRepositoryProvider.overrideWith((ref) => _FakeMailboxRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

final _account = MailAccount(
  id: 'app-test-2@finestar.hr',
  email: 'app-test-2@finestar.hr',
  displayName: 'App Test 2',
  connectionSettings: const ConnectionSettings(
    imapHost: 'mail.finestar.hr',
    imapPort: 993,
    imapSecurity: MailSecurity.sslTls,
    smtpHost: 'mail.finestar.hr',
    smtpPort: 465,
    smtpSecurity: MailSecurity.sslTls,
  ),
  createdAt: DateTime(2026, 4, 16),
);

class _FakeMailboxRepository implements MailboxRepository {
  @override
  Future<List<MailFolder>> getFolders(String accountId) async => const [
    MailFolder(
      id: 'app-test-2@finestar.hr:drafts',
      name: 'Drafts',
      path: 'Drafts',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:junk',
      name: 'Junk',
      path: 'Junk',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:trash',
      name: 'Trash',
      path: 'Trash',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:sent',
      name: 'Sent',
      path: 'Sent',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:projects',
      name: 'Projects',
      path: 'Projects',
      isInbox: false,
    ),
  ];

  @override
  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    if (folder.path == 'Sent') {
      return [
        MailMessageSummary(
          id: '$accountId:sent:imap:1',
          folderId: folder.id,
          subject: 'Sent sync smoke',
          sender: 'app-test-2@finestar.hr',
          preview: 'This message came from the selected Sent folder.',
          receivedAt: DateTime(2026, 4, 16),
          isRead: true,
          hasAttachments: false,
          sequence: 1,
        ),
      ];
    }
    return const [];
  }

  @override
  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  }) async => const [];
}
