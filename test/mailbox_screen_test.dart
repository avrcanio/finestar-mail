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
    expect(find.byTooltip('Manage account'), findsOneWidget);

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

    await tester.tap(find.byTooltip('Manage account'));
    await tester.pumpAndSettle();

    expect(find.text('Manage your account'), findsOneWidget);
  });

  testWidgets('unread, important, and pinned message states render', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Pinned important'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    final unreadCard = tester.widget<Card>(
      find
          .ancestor(
            of: find.text('Pinned important'),
            matching: find.byType(Card),
          )
          .first,
    );
    expect(unreadCard.color, const Color(0xFFEAF4FF));
  });

  testWidgets('long press opens message status actions and toggles read', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository();
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Pinned important'));
    await tester.pumpAndSettle();

    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('Remove important'), findsOneWidget);
    expect(find.text('Unpin'), findsOneWidget);

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();

    expect(repository.messages.first.isRead, isTrue);
  });
}

Widget _buildTestApp({_FakeMailboxRepository? repository}) {
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
      mailboxRepositoryProvider.overrideWith(
        (ref) => repository ?? _FakeMailboxRepository(),
      ),
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
  _FakeMailboxRepository()
    : messages = [
        MailMessageSummary(
          id: 'app-test-2@finestar.hr:inbox:imap:2',
          folderId: 'app-test-2@finestar.hr:inbox',
          subject: 'Pinned important',
          sender: 'client@finestar.hr',
          preview: 'Pinned unread message',
          receivedAt: DateTime(2026, 4, 16, 8),
          isRead: false,
          isImportant: true,
          isPinned: true,
          hasAttachments: false,
          sequence: 2,
        ),
        MailMessageSummary(
          id: 'app-test-2@finestar.hr:inbox:imap:3',
          folderId: 'app-test-2@finestar.hr:inbox',
          subject: 'Read normal',
          sender: 'team@finestar.hr',
          preview: 'Regular read message',
          receivedAt: DateTime(2026, 4, 16, 9),
          isRead: true,
          hasAttachments: false,
          sequence: 3,
        ),
      ];

  final List<MailMessageSummary> messages;

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
    return messages;
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
  Future<String?> findCachedMessageId({
    required String accountId,
    String? localMessageId,
    String? folder,
    String? uid,
    String? rfcMessageId,
    String? subject,
    String? sender,
  }) async => localMessageId;

  @override
  Future<void> setMessageRead({
    required String accountId,
    required String messageId,
    required bool isRead,
  }) async {
    _updateMessage(messageId, (message) {
      return MailMessageSummary(
        id: message.id,
        folderId: message.folderId,
        subject: message.subject,
        sender: message.sender,
        preview: message.preview,
        receivedAt: message.receivedAt,
        isRead: isRead,
        hasAttachments: message.hasAttachments,
        sequence: message.sequence,
        isImportant: message.isImportant,
        isPinned: message.isPinned,
      );
    });
  }

  @override
  Future<void> setMessageImportant({
    required String accountId,
    required String messageId,
    required bool isImportant,
  }) async {
    _updateMessage(messageId, (message) {
      return MailMessageSummary(
        id: message.id,
        folderId: message.folderId,
        subject: message.subject,
        sender: message.sender,
        preview: message.preview,
        receivedAt: message.receivedAt,
        isRead: message.isRead,
        hasAttachments: message.hasAttachments,
        sequence: message.sequence,
        isImportant: isImportant,
        isPinned: message.isPinned,
      );
    });
  }

  @override
  Future<void> setMessagePinned({
    required String accountId,
    required String messageId,
    required bool isPinned,
  }) async {
    _updateMessage(messageId, (message) {
      return MailMessageSummary(
        id: message.id,
        folderId: message.folderId,
        subject: message.subject,
        sender: message.sender,
        preview: message.preview,
        receivedAt: message.receivedAt,
        isRead: message.isRead,
        hasAttachments: message.hasAttachments,
        sequence: message.sequence,
        isImportant: message.isImportant,
        isPinned: isPinned,
      );
    });
  }

  void _updateMessage(
    String messageId,
    MailMessageSummary Function(MailMessageSummary message) update,
  ) {
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index != -1) {
      messages[index] = update(messages[index]);
    }
  }

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  }) async => const [];
}
