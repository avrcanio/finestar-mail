import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/core/theme/app_theme.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/compose/domain/entities/reply_context.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_delete_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_page.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_thread.dart';
import 'package:finestar_mail/features/mailbox/domain/repositories/mailbox_repository.dart';
import 'package:finestar_mail/features/mailbox/presentation/message_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('message detail renders chronological thread content', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text(_thread.subject), findsOneWidget);
    expect(find.textContaining('INBOX'), findsOneWidget);
    expect(find.textContaining(_firstMessage.sender), findsOneWidget);
    expect(find.textContaining(_secondMessage.sender), findsOneWidget);
    expect(find.textContaining('Sent'), findsWidgets);
    expect(find.text(_firstMessage.visibleBody), findsOneWidget);
    expect(find.text(_secondMessage.visibleBody), findsOneWidget);
    expect(find.text('Show quoted text'), findsOneWidget);
  });

  testWidgets('collapsed thread item expands when tapped', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    final bodyFinder = find.text(_firstMessage.visibleBody);
    expect(tester.widget<Text>(bodyFinder).maxLines, 2);

    await tester.tap(bodyFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(bodyFinder).maxLines, isNull);
  });

  testWidgets('quoted text can be shown and hidden', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('original project kickoff'), findsNothing);

    await tester.tap(find.text('Show quoted text'));
    await tester.pumpAndSettle();

    expect(find.text('Hide quoted text'), findsOneWidget);
    expect(find.textContaining('original project kickoff'), findsOneWidget);

    await tester.tap(find.text('Hide quoted text'));
    await tester.pumpAndSettle();

    expect(find.text('Show quoted text'), findsOneWidget);
    expect(find.textContaining('original project kickoff'), findsNothing);
  });

  testWidgets('per-message reply and forward use tapped message context', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Reply').last);
    await tester.pumpAndSettle();

    expect(
      find.text('reply:${_secondMessage.id}:${_secondMessage.sender}'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Forward').first);
    await tester.pumpAndSettle();

    expect(find.text('forward:${_firstMessage.id}:'), findsOneWidget);
  });

  testWidgets('opening message detail marks selected message read', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository();
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    expect(repository.markedReadMessageIds, contains(_secondMessage.id));
  });

  testWidgets(
    'delete moves selected detail message to trash and navigates back',
    (tester) async {
      final repository = _FakeMailboxRepository();
      await tester.pumpWidget(_buildTestApp(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(repository.deletedMessageIds, [_secondMessage.id]);
      expect(find.text('Inbox route reached'), findsOneWidget);
    },
  );
}

Widget _buildTestApp({_FakeMailboxRepository? repository}) {
  final router = GoRouter(
    initialLocation: AppRoute.messageDetail.path.replaceFirst(
      ':id',
      _thread.selectedMessageId,
    ),
    routes: [
      GoRoute(
        path: AppRoute.messageDetail.path,
        builder: (context, state) =>
            MessageDetailScreen(messageId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoute.compose.path,
        builder: (context, state) {
          final replyContext = state.extra! as ReplyContext;
          return Scaffold(
            appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
            body: Text(
              '${replyContext.action.name}:${replyContext.targetMessageId}:${replyContext.recipients.join(',')}',
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoute.inbox.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Inbox route reached'))),
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
    child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
}

final _account = MailAccount(
  id: 'avrcan@finestar.hr',
  email: 'avrcan@finestar.hr',
  displayName: 'Ante Vrcan',
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

final _firstMessage = MailThreadMessage(
  id: 'message-1',
  folderId: 'avrcan@finestar.hr:inbox',
  folderName: 'INBOX',
  subject: 'probni mail',
  sender: 'ante@vitalgroupsa.com',
  recipients: const ['avrcan@finestar.hr'],
  bodyPlain:
      'Ovo je prvi dio razgovora s dugim tekstom koji je defaultno skracen u thread kartici.',
  bodyHtml: null,
  receivedAt: DateTime(2026, 4, 16, 8, 2),
  messageIdHeader: '<message-1@finestar.hr>',
  inReplyToHeader: null,
  referencesHeader: null,
);

final _secondMessage = MailThreadMessage(
  id: 'message-2',
  folderId: 'avrcan@finestar.hr:sent',
  folderName: 'Sent',
  subject: 'Re: probni mail',
  sender: 'avrcan@finestar.hr',
  recipients: const ['ante@vitalgroupsa.com'],
  bodyPlain:
      'Eto moj probni mail neka si mi napisao kako mislis da trebamo raditi.\n\nOn Thu, Apr 16, 2026 at 8:02 AM Ante wrote:\n> original project kickoff',
  bodyHtml: null,
  receivedAt: DateTime(2026, 4, 16, 8, 5),
  messageIdHeader: '<message-2@finestar.hr>',
  inReplyToHeader: '<message-1@finestar.hr>',
  referencesHeader: '<message-1@finestar.hr>',
);

final _thread = MailThread(
  subject: 'probni mail',
  selectedMessageId: _secondMessage.id,
  messages: [_firstMessage, _secondMessage],
);

class _FakeMailboxRepository implements MailboxRepository {
  final markedReadMessageIds = <String>[];
  final deletedMessageIds = <String>[];

  @override
  Future<List<MailFolder>> getFolders(String accountId) async => const [];

  @override
  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async => const [];

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
  }) async => _thread;

  @override
  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<MailDeleteResult> moveMessagesToTrash({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async {
    deletedMessageIds.addAll(messageIds);
    return MailDeleteResult(movedMessageIds: messageIds, failed: const []);
  }

  @override
  Future<MailDeleteResult> moveMessageToTrash({
    required String accountId,
    required String messageId,
  }) async {
    deletedMessageIds.add(messageId);
    return MailDeleteResult(movedMessageIds: [messageId], failed: const []);
  }

  @override
  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
    bool forceRefresh = false,
  }) async => const MailMessagePage(messages: [], hasMore: false);

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
    if (isRead) {
      markedReadMessageIds.add(messageId);
    }
  }

  @override
  Future<void> setMessageImportant({
    required String accountId,
    required String messageId,
    required bool isImportant,
  }) async {}

  @override
  Future<void> setMessagePinned({
    required String accountId,
    required String messageId,
    required bool isPinned,
  }) async {}

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  }) async => const [];
}
