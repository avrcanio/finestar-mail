import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_delete_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_conversation.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_attachment.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_page.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_restore_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_thread.dart';
import 'package:finestar_mail/features/mailbox/domain/repositories/mailbox_repository.dart';
import 'package:finestar_mail/features/mailbox/presentation/mailbox_controller.dart';
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
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Junk'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('drawer renders nested folders as collapsible tree', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();

    expect(find.text('Izvodi'), findsOneWidget);
    expect(find.text('Izvodi.HPB'), findsNothing);
    expect(find.text('HPB'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Izvodi'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Expand folder'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HPB'), findsOneWidget);
    expect(find.text('Kent'), findsOneWidget);
    expect(find.text('PBZ'), findsOneWidget);
    expect(find.text('Izvodi.HPB'), findsNothing);

    final parentTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Izvodi'), matching: find.byType(ListTile)),
    );
    final childTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('HPB'), matching: find.byType(ListTile)),
    );
    final parentPadding = parentTile.contentPadding! as EdgeInsets;
    final childPadding = childTile.contentPadding! as EdgeInsets;
    expect(childPadding.left, greaterThan(parentPadding.left));

    await tester.tap(find.byTooltip('Collapse folder'));
    await tester.pumpAndSettle();

    expect(find.text('HPB'), findsNothing);
  });

  testWidgets('selecting parent folder opens messages with canonical path', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository();
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Izvodi'));
    await tester.pumpAndSettle();

    expect(find.text('Izvodi sync smoke'), findsOneWidget);
    expect(repository.requestedFolderPaths, contains('Izvodi'));
  });

  testWidgets('selecting nested folder opens messages with canonical path', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository();
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Izvodi'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Expand folder'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('HPB'));
    await tester.pumpAndSettle();

    expect(find.text('HPB sync smoke'), findsOneWidget);
    expect(repository.requestedFolderPaths, contains('Izvodi.HPB'));
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

  testWidgets('mailbox list shows paperclip for attachment summary flag', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.attach_file), findsOneWidget);
  });

  testWidgets('search results do not receive conversation-only styling', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Pinned');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Pinned important'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(
      find.byKey(
        const ValueKey(
          'latest-conversation-message-app-test-2@finestar.hr:inbox:imap:2',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('mailbox renders backend conversations expanded by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(
          threadedConversations: [_threadedConversation],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thread root'), findsOneWidget);
    expect(find.text('Re: Fwd: Thread root'), findsNothing);
    expect(find.text('Thread reply one'), findsOneWidget);
    expect(find.text('Thread reply two'), findsOneWidget);
    expect(find.text('2 replies'), findsOneWidget);
    expect(find.text('Sent'), findsNothing);
    expect(
      find.byKey(const ValueKey('latest-conversation-message-reply-2')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Thread reply one')).dx,
      greaterThan(tester.getTopLeft(find.text('Thread root')).dx),
    );
  });

  testWidgets('conversation reply tap opens reply detail row', (tester) async {
    final repository = _FakeMailboxRepository(
      threadedConversations: [_threadedConversation],
    );
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thread reply one'));
    await tester.pumpAndSettle();

    expect(find.text('detail:reply-1'), findsOneWidget);
  });

  testWidgets('unified conversation renders outbound row and opens exact row', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository(
      threadedConversations: [_unifiedConversation],
    );
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Unified root'), findsOneWidget);
    expect(find.text('Unified sent reply'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('latest-conversation-message-unified-sent-1')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.attach_file), findsOneWidget);

    await tester.tap(find.text('Unified sent reply'));
    await tester.pumpAndSettle();

    expect(find.text('detail:unified-sent-1'), findsOneWidget);
  });

  testWidgets('conversation reply selection targets reply row', (tester) async {
    final repository = _FakeMailboxRepository(
      threadedConversations: [_threadedConversation],
    );
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Thread reply two'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(CircleAvatar),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Move selected to Trash'));
    await tester.pumpAndSettle();

    expect(repository.deletedMessageIds, ['reply-2']);
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

  testWidgets('conversation list does not request flat cursor pagination', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository(initialMessageCount: 24);
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Older backend page'), findsNothing);

    await tester.drag(find.byType(ListView).last, const Offset(0, -2500));
    await tester.pumpAndSettle();

    expect(find.text('Older backend page'), findsNothing);
    expect(repository.pageRequests, isEmpty);
  });

  test('mailbox controller prevents duplicate concurrent load more', () async {
    final repository = _FakeMailboxRepository(initialMessageCount: 8);
    final container = ProviderContainer(
      overrides: [
        activeAccountProvider.overrideWith((ref) async => _account),
        mailboxRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(
      mailboxMessagesControllerProvider(_inboxFolder).future,
    );
    final notifier = container.read(
      mailboxMessagesControllerProvider(_inboxFolder).notifier,
    );

    await Future.wait([notifier.loadMore(), notifier.loadMore()]);

    final state = container
        .read(mailboxMessagesControllerProvider(_inboxFolder))
        .value!;
    expect(state.messages.last.subject, 'Older backend page');
    expect(
      repository.pageRequests.where((cursor) => cursor == '2'),
      hasLength(1),
    );
  });

  testWidgets('avatar selection deletes selected messages', (tester) async {
    final repository = _FakeMailboxRepository(backendIds: true);
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Select message').first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Move selected to Trash'));
    await tester.pumpAndSettle();

    expect(repository.deletedMessageIds, [
      'app-test-2@finestar.hr:inbox:api:2',
    ]);
    expect(find.text('Pinned important'), findsNothing);
  });

  testWidgets('Trash selection restores selected messages to INBOX', (
    tester,
  ) async {
    final repository = _FakeMailboxRepository(backendIds: true);
    await tester.pumpWidget(_buildTestApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Select message').first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Move selected to Trash'), findsNothing);
    await tester.tap(find.byTooltip('Restore selected to INBOX'));
    await tester.pumpAndSettle();

    expect(repository.restoredMessageIds, [
      'app-test-2@finestar.hr:trash:api:2',
    ]);
    expect(find.text('Trash message'), findsNothing);
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
      GoRoute(
        path: AppRoute.messageDetail.path,
        builder: (context, state) => Scaffold(
          body: Center(child: Text('detail:${state.pathParameters['id']}')),
        ),
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

const _inboxFolder = MailFolder(
  id: 'app-test-2@finestar.hr:inbox',
  name: 'INBOX',
  path: 'INBOX',
  isInbox: true,
);

final _threadRoot = MailMessageSummary(
  id: 'root-1',
  folderId: 'app-test-2@finestar.hr:inbox',
  subject: 'Re: Fwd: Thread root',
  sender: 'client@finestar.hr',
  preview: 'Root preview',
  receivedAt: DateTime(2026, 4, 16, 8),
  isRead: false,
  isImportant: true,
  hasAttachments: false,
  sequence: 20,
);

final _threadReplyOne = MailMessageSummary(
  id: 'reply-1',
  folderId: 'app-test-2@finestar.hr:inbox',
  subject: 'Thread reply one',
  sender: 'app-test-2@finestar.hr',
  preview: 'First reply preview',
  receivedAt: DateTime(2026, 4, 16, 9),
  isRead: true,
  hasAttachments: false,
  sequence: 21,
);

final _threadReplyTwo = MailMessageSummary(
  id: 'reply-2',
  folderId: 'app-test-2@finestar.hr:inbox',
  subject: 'Thread reply two',
  sender: 'client@finestar.hr',
  preview: 'Second reply preview',
  receivedAt: DateTime(2026, 4, 16, 10),
  isRead: true,
  hasAttachments: true,
  sequence: 22,
);

final _threadedConversation = MailConversation(
  id: 'conversation-1',
  messageCount: 3,
  replyCount: 2,
  hasUnread: true,
  hasAttachments: true,
  hasVisibleAttachments: true,
  participants: const [
    MailConversationParticipant(name: 'Client', email: 'client@finestar.hr'),
  ],
  rootMessage: _threadRoot,
  replies: [_threadReplyOne, _threadReplyTwo],
  latestDate: DateTime(2026, 4, 16, 10),
);

final _unifiedRoot = MailMessageSummary(
  id: 'unified-root-1',
  folderId: 'app-test-2@finestar.hr:inbox',
  subject: 'Unified root',
  sender: 'client@finestar.hr',
  preview: 'Unified root preview',
  receivedAt: DateTime(2026, 4, 16, 8),
  isRead: false,
  hasAttachments: false,
  sequence: 30,
);

final _unifiedSentReply = MailMessageSummary(
  id: 'unified-sent-1',
  folderId: 'app-test-2@finestar.hr:sent',
  subject: 'Unified sent reply',
  sender: 'app-test-2@finestar.hr',
  preview: 'Outbound reply preview',
  receivedAt: DateTime(2026, 4, 16, 9),
  isRead: true,
  hasAttachments: false,
  sequence: 31,
);

final _unifiedConversation = MailConversation(
  id: 'unified-conversation-1',
  messageCount: 2,
  replyCount: 1,
  hasUnread: true,
  hasAttachments: true,
  hasVisibleAttachments: true,
  participants: const [
    MailConversationParticipant(name: 'Client', email: 'client@finestar.hr'),
  ],
  rootMessage: _unifiedRoot,
  replies: [_unifiedSentReply],
  latestDate: DateTime(2026, 4, 16, 9),
  timelineMessages: [
    MailConversationMessage(
      message: _unifiedRoot,
      direction: MailConversationDirection.inbound,
    ),
    MailConversationMessage(
      message: _unifiedSentReply,
      direction: MailConversationDirection.outbound,
    ),
  ],
);

class _FakeMailboxRepository implements MailboxRepository {
  _FakeMailboxRepository({
    int initialMessageCount = 2,
    bool backendIds = false,
    this.threadedConversations,
  }) : messages = [
         MailMessageSummary(
           id: backendIds
               ? 'app-test-2@finestar.hr:inbox:api:2'
               : 'app-test-2@finestar.hr:inbox:imap:2',
           folderId: 'app-test-2@finestar.hr:inbox',
           subject: 'Pinned important',
           sender: 'client@finestar.hr',
           preview: 'Pinned unread message',
           receivedAt: DateTime(2026, 4, 16, 8),
           isRead: false,
           isImportant: true,
           isPinned: true,
           hasAttachments: true,
           sequence: 2,
         ),
         MailMessageSummary(
           id: backendIds
               ? 'app-test-2@finestar.hr:inbox:api:3'
               : 'app-test-2@finestar.hr:inbox:imap:3',
           folderId: 'app-test-2@finestar.hr:inbox',
           subject: 'Read normal',
           sender: 'team@finestar.hr',
           preview: 'Regular read message',
           receivedAt: DateTime(2026, 4, 16, 9),
           isRead: true,
           hasAttachments: false,
           sequence: 3,
         ),
         for (var index = 4; index < initialMessageCount + 2; index++)
           MailMessageSummary(
             id: 'app-test-2@finestar.hr:inbox:imap:$index',
             folderId: 'app-test-2@finestar.hr:inbox',
             subject: 'Inbox message $index',
             sender: 'team@finestar.hr',
             preview: 'Extra message $index',
             receivedAt: DateTime(
               2026,
               4,
               16,
               9,
             ).subtract(Duration(minutes: index)),
             isRead: true,
             hasAttachments: false,
             sequence: index,
           ),
       ];

  final List<MailMessageSummary> messages;
  final List<MailConversation>? threadedConversations;
  final trashMessages = <MailMessageSummary>[
    MailMessageSummary(
      id: 'app-test-2@finestar.hr:trash:api:2',
      folderId: 'app-test-2@finestar.hr:trash',
      subject: 'Trash message',
      sender: 'client@finestar.hr',
      preview: 'Restore me.',
      receivedAt: DateTime(2026, 4, 16, 8),
      isRead: true,
      hasAttachments: false,
      sequence: 2,
    ),
  ];
  final pageRequests = <String?>[];
  final requestedFolderPaths = <String>[];
  final deletedMessageIds = <String>[];
  final restoredMessageIds = <String>[];

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
    MailFolder(
      id: 'app-test-2@finestar.hr:izvodi',
      name: 'Izvodi',
      path: 'Izvodi',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:izvodi.hpb',
      name: 'Izvodi.HPB',
      path: 'Izvodi.HPB',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:izvodi.kent',
      name: 'Izvodi.Kent',
      path: 'Izvodi.Kent',
      isInbox: false,
    ),
    MailFolder(
      id: 'app-test-2@finestar.hr:izvodi.pbz',
      name: 'Izvodi.PBZ',
      path: 'Izvodi.PBZ',
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
    requestedFolderPaths.add(folder.path);
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
    if (folder.path == 'Trash') {
      return trashMessages;
    }
    if (folder.path == 'Izvodi') {
      return [
        MailMessageSummary(
          id: '$accountId:izvodi:api:1',
          folderId: folder.id,
          subject: 'Izvodi sync smoke',
          sender: 'izvodi@example.test',
          preview: 'This message came from the selected Izvodi folder.',
          receivedAt: DateTime(2026, 4, 16),
          isRead: true,
          hasAttachments: false,
          sequence: 1,
        ),
      ];
    }
    if (folder.path == 'Izvodi.HPB') {
      return [
        MailMessageSummary(
          id: '$accountId:izvodi.hpb:api:1',
          folderId: folder.id,
          subject: 'HPB sync smoke',
          sender: 'hpb@example.test',
          preview: 'This message came from the selected HPB folder.',
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
  Future<List<MailConversation>> getConversations({
    required String accountId,
    required MailFolder folder,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    if (threadedConversations != null && folder.path == 'INBOX') {
      requestedFolderPaths.add(folder.path);
      return threadedConversations!;
    }
    final folderMessages = await getMessages(
      accountId: accountId,
      folder: folder,
      pageSize: limit,
      forceRefresh: forceRefresh,
    );
    return folderMessages
        .map(
          (message) => MailConversation(
            id: message.id,
            messageCount: 1,
            replyCount: 0,
            hasUnread: !message.isRead,
            hasAttachments: message.hasAttachments,
            hasVisibleAttachments: message.hasAttachments,
            participants: [
              MailConversationParticipant(name: '', email: message.sender),
            ],
            rootMessage: message,
            replies: const [],
            latestDate: message.receivedAt,
          ),
        )
        .toList();
  }

  @override
  Future<List<MailConversation>> getUnifiedConversations({
    required String accountId,
    int limit = 50,
    bool forceRefresh = false,
  }) {
    return getConversations(
      accountId: accountId,
      folder: _inboxFolder,
      limit: limit,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
    bool forceRefresh = false,
  }) async {
    pageRequests.add(beforeUid);
    if (beforeUid == '2') {
      return MailMessagePage(
        messages: [
          MailMessageSummary(
            id: '$accountId:inbox:api:1',
            folderId: folder.id,
            subject: 'Older backend page',
            sender: 'archive@finestar.hr',
            preview: 'Loaded from older cursor.',
            receivedAt: DateTime(2026, 4, 15),
            isRead: true,
            hasAttachments: false,
            sequence: 1,
          ),
        ],
        hasMore: false,
      );
    }
    final pageMessages = await getMessages(
      accountId: accountId,
      folder: folder,
      pageSize: pageSize,
      forceRefresh: forceRefresh,
    );
    return MailMessagePage(
      messages: pageMessages,
      hasMore: folder.path != 'Sent',
      nextBeforeUid: folder.path == 'Sent' ? null : '2',
    );
  }

  @override
  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedMailAttachment> downloadAttachment({
    required String accountId,
    required String messageId,
    required MailMessageAttachment attachment,
  }) async => const DownloadedMailAttachment(
    filename: 'attachment.txt',
    contentType: 'text/plain',
    bytes: [104, 105],
  );

  @override
  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MailDeleteResult> moveMessagesToTrash({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async {
    deletedMessageIds.addAll(messageIds);
    messages.removeWhere((message) => messageIds.contains(message.id));
    return MailDeleteResult(movedMessageIds: messageIds, failed: const []);
  }

  @override
  Future<MailDeleteResult> moveMessageToTrash({
    required String accountId,
    required String messageId,
  }) async {
    return moveMessagesToTrash(
      accountId: accountId,
      folder: _inboxFolder,
      messageIds: [messageId],
    );
  }

  @override
  Future<MailRestoreResult> restoreMessagesToInbox({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async {
    restoredMessageIds.addAll(messageIds);
    trashMessages.removeWhere((message) => messageIds.contains(message.id));
    return MailRestoreResult(restoredMessageIds: messageIds, failed: const []);
  }

  @override
  Future<MailRestoreResult> restoreMessageToInbox({
    required String accountId,
    required String messageId,
  }) async {
    return restoreMessagesToInbox(
      accountId: accountId,
      folder: const MailFolder(
        id: 'app-test-2@finestar.hr:trash',
        name: 'Trash',
        path: 'Trash',
        isInbox: false,
      ),
      messageIds: [messageId],
    );
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
  }) async {
    final normalizedQuery = query.toLowerCase();
    return messages
        .where(
          (message) =>
              message.subject.toLowerCase().contains(normalizedQuery) ||
              message.sender.toLowerCase().contains(normalizedQuery) ||
              message.preview.toLowerCase().contains(normalizedQuery),
        )
        .take(limit)
        .toList();
  }
}
