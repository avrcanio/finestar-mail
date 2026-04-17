import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/core/theme/app_theme.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/compose/domain/entities/reply_context.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_delete_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_attachment.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_page.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_restore_result.dart';
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

  testWidgets('message detail subject uses compact typography', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    final subjectText = tester.widget<Text>(find.text(_thread.subject));

    expect(subjectText.style?.fontSize, 20);
    expect(subjectText.style?.fontWeight, FontWeight.w600);
    expect(subjectText.style?.height, 1.06);
  });

  testWidgets('message detail renders long subject without layout errors', (
    tester,
  ) async {
    const longSubject =
        'Nuvola Studio: Vasa narudzba od 11 veljace, 2026 je poslana i spremna za preuzimanje';
    final longSubjectMessage = MailThreadMessage(
      id: 'long-subject-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: longSubject,
      sender: 'shop@nuvola.example',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'Long subject body.',
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<long-subject-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final thread = MailThread(
      subject: longSubject,
      selectedMessageId: longSubjectMessage.id,
      messages: [longSubjectMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: longSubjectMessage.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(longSubject), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('message detail renders attachment metadata', (tester) async {
    final attachmentMessage = MailThreadMessage(
      id: 'avrcan@finestar.hr:inbox:api:42',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Attachment smoke',
      sender: 'ante@vitalgroupsa.com',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'See attachment.',
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 10),
      messageIdHeader: '<attachment@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
      attachments: const [
        MailMessageAttachment(
          id: 'att_1',
          filename: 'smoke.txt',
          contentType: 'text/plain',
          sizeBytes: 2,
          disposition: 'attachment',
          isInline: false,
        ),
      ],
    );
    final thread = MailThread(
      subject: 'Attachment smoke',
      selectedMessageId: attachmentMessage.id,
      messages: [attachmentMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: attachmentMessage.id,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('smoke.txt'), findsOneWidget);
    expect(find.text('text/plain - 2 B'), findsOneWidget);
  });

  testWidgets('message detail hides only referenced inline cid attachments', (
    tester,
  ) async {
    const htmlBody = '<p>Logo <img src="cid:image001.png@example"></p>';
    final inlineMessage = MailThreadMessage(
      id: 'avrcan@finestar.hr:inbox:api:42',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Inline images',
      sender: 'ante@vitalgroupsa.com',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'See logo.',
      bodyHtml: htmlBody,
      receivedAt: DateTime(2026, 4, 16, 10),
      messageIdHeader: '<inline@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
      attachments: const [
        MailMessageAttachment(
          id: 'img_1',
          filename: 'image001.png',
          contentType: 'image/png',
          sizeBytes: 3,
          disposition: 'inline',
          isInline: true,
          contentId: 'image001.png@example',
        ),
        MailMessageAttachment(
          id: 'img_2',
          filename: 'image002.png',
          contentType: 'image/png',
          sizeBytes: 4,
          disposition: 'attachment',
          isInline: false,
          contentId: 'image002.png@example',
          isVisible: false,
        ),
        MailMessageAttachment(
          id: 'pdf_1',
          filename: 'invoice.pdf',
          contentType: 'application/pdf',
          sizeBytes: 5,
          disposition: 'attachment',
          isInline: false,
          isVisible: true,
        ),
      ],
    );
    final thread = MailThread(
      subject: 'Inline images',
      selectedMessageId: inlineMessage.id,
      messages: [inlineMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: inlineMessage.id,
        emailHtmlViewBuilder: (html) => Text('html-view:$html'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('html-view:$htmlBody'), findsOneWidget);
    expect(find.text('image001.png'), findsNothing);
    expect(find.text('image002.png'), findsNothing);
    expect(find.text('invoice.pdf'), findsOneWidget);
  });

  testWidgets('expanded HTML message renders HTML view instead of plain text', (
    tester,
  ) async {
    const htmlBody =
        '<h1>Narudzba je poslana</h1><table><tr><td>Nuvola</td></tr></table>';
    final htmlMessage = MailThreadMessage(
      id: 'html-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Nuvola Studio',
      sender: 'shop@nuvola.example',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'Plain Nuvola fallback',
      bodyHtml: htmlBody,
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<html-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final thread = MailThread(
      subject: 'Nuvola Studio',
      selectedMessageId: htmlMessage.id,
      messages: [htmlMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: htmlMessage.id,
        emailHtmlViewBuilder: (html) => Text('html-view:$html'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plain Nuvola fallback'), findsNothing);
    expect(find.text('html-view:$htmlBody'), findsOneWidget);
  });

  test(
    'HTML wrapper injects mobile-first fit-to-width CSS after raw email',
    () {
      const rawHtml = '''
<style>
@media only screen and (max-width: 660px) {
  .full-header {
    width: 660px !important;
    min-width: 660px !important;
  }
}
</style>
<table class="full-header" width="660" style="width: 660px;">
  <tr>
    <td width="600"><img src="hero.png" width="660"></td>
  </tr>
</table>
<pre>unbreakable content</pre>
''';

      final wrappedHtml = wrapEmailHtmlForRendering(rawHtml);

      expect(wrappedHtml, contains('width: 100% !important;'));
      expect(wrappedHtml, contains('max-width: 100% !important;'));
      expect(wrappedHtml, contains('overflow-x: auto;'));
      expect(wrappedHtml, contains('.full-header'));
      expect(wrappedHtml, contains('table[width]'));
      expect(wrappedHtml, contains('table[style*="width"]'));
      expect(wrappedHtml, contains('img[width]'));
      expect(wrappedHtml, contains('height: auto !important;'));
      expect(wrappedHtml, contains('pre,'));
      expect(wrappedHtml, contains('overflow-x: auto !important;'));
      expect(wrappedHtml, contains('-webkit-overflow-scrolling: touch;'));
      expect(
        wrappedHtml.lastIndexOf('data-finestar-email-fit'),
        greaterThan(wrappedHtml.indexOf('width: 660px !important')),
      );
    },
  );

  testWidgets('plain text remains fallback when HTML body is empty', (
    tester,
  ) async {
    final plainMessage = MailThreadMessage(
      id: 'plain-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'PBZ',
      sender: 'pbz@example.test',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'PBZ plain text body',
      bodyHtml: '   ',
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<plain-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final thread = MailThread(
      subject: 'PBZ',
      selectedMessageId: plainMessage.id,
      messages: [plainMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: plainMessage.id,
        emailHtmlViewBuilder: (html) => Text('html-view:$html'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PBZ plain text body'), findsOneWidget);
    expect(find.textContaining('html-view:'), findsNothing);
  });

  testWidgets('long plain body uses linked inner scroll before outer scroll', (
    tester,
  ) async {
    final longBody = List.generate(
      90,
      (index) => 'Long body line ${index + 1}',
    ).join('\n');
    final longMessage = MailThreadMessage(
      id: 'long-plain-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Long body scroll',
      sender: 'shop@nuvola.example',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: longBody,
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<long-plain-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final trailingMessage = MailThreadMessage(
      id: 'trailing-plain-message',
      folderId: 'avrcan@finestar.hr:sent',
      folderName: 'Sent',
      subject: 'Re: Long body scroll',
      sender: 'avrcan@finestar.hr',
      recipients: const ['shop@nuvola.example'],
      bodyPlain: List.generate(
        18,
        (index) => 'Trailing reply line ${index + 1}',
      ).join('\n'),
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 11, 5),
      messageIdHeader: '<trailing-plain-message@finestar.hr>',
      inReplyToHeader: '<long-plain-message@finestar.hr>',
      referencesHeader: '<long-plain-message@finestar.hr>',
    );
    final thread = MailThread(
      subject: 'Long body scroll',
      selectedMessageId: longMessage.id,
      messages: [longMessage, trailingMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: longMessage.id,
      ),
    );
    await tester.pumpAndSettle();

    final bodyTarget = find
        .byKey(const ValueKey('message-body-linked-scroll-view'))
        .first;
    final outerScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('message-detail-outer-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final innerScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('message-body-inner-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final outerOffsetBefore = outerScrollable.position.pixels;
    final innerOffsetBefore = innerScrollable.position.pixels;

    await tester.drag(bodyTarget, const Offset(0, -140));
    await tester.pumpAndSettle();

    expect(innerScrollable.position.pixels, greaterThan(innerOffsetBefore));
    expect(outerScrollable.position.pixels, outerOffsetBefore);

    await tester.drag(bodyTarget, const Offset(0, -3200));
    await tester.pumpAndSettle();

    expect(
      innerScrollable.position.pixels,
      innerScrollable.position.maxScrollExtent,
    );
    expect(outerScrollable.position.pixels, greaterThan(outerOffsetBefore));
  });

  testWidgets('short plain body does not force an inner scrollbar', (
    tester,
  ) async {
    final shortMessage = MailThreadMessage(
      id: 'short-plain-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Short body scroll',
      sender: 'shop@nuvola.example',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'Short body.',
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<short-plain-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final thread = MailThread(
      subject: 'Short body scroll',
      selectedMessageId: shortMessage.id,
      messages: [shortMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: shortMessage.id,
      ),
    );
    await tester.pumpAndSettle();

    final innerScrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('message-body-inner-scrollbar')),
    );

    expect(innerScrollbar.thumbVisibility, isFalse);
  });

  testWidgets('collapsed HTML message shows plain preview until expanded', (
    tester,
  ) async {
    const htmlBody = '<table><tr><td>Expanded HTML order</td></tr></table>';
    final htmlMessage = MailThreadMessage(
      id: 'html-collapsed-message',
      folderId: 'avrcan@finestar.hr:inbox',
      folderName: 'INBOX',
      subject: 'Nuvola collapsed',
      sender: 'shop@nuvola.example',
      recipients: const ['avrcan@finestar.hr'],
      bodyPlain: 'Collapsed plain preview',
      bodyHtml: htmlBody,
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<html-collapsed-message@finestar.hr>',
      inReplyToHeader: null,
      referencesHeader: null,
    );
    final selectedPlainMessage = MailThreadMessage(
      id: 'selected-plain-message',
      folderId: 'avrcan@finestar.hr:sent',
      folderName: 'Sent',
      subject: 'Re: Nuvola collapsed',
      sender: 'avrcan@finestar.hr',
      recipients: const ['shop@nuvola.example'],
      bodyPlain: 'Selected plain response',
      bodyHtml: null,
      receivedAt: DateTime(2026, 4, 16, 11, 5),
      messageIdHeader: '<selected-plain-message@finestar.hr>',
      inReplyToHeader: '<html-collapsed-message@finestar.hr>',
      referencesHeader: '<html-collapsed-message@finestar.hr>',
    );
    final thread = MailThread(
      subject: 'Nuvola collapsed',
      selectedMessageId: selectedPlainMessage.id,
      messages: [htmlMessage, selectedPlainMessage],
    );

    await tester.pumpWidget(
      _buildTestApp(
        repository: _FakeMailboxRepository(thread: thread),
        initialMessageId: selectedPlainMessage.id,
        emailHtmlViewBuilder: (html) => Text('html-view:$html'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collapsed plain preview'), findsOneWidget);
    expect(find.text('html-view:$htmlBody'), findsNothing);

    await tester.tap(find.text('Collapsed plain preview'));
    await tester.pumpAndSettle();

    expect(find.text('Collapsed plain preview'), findsNothing);
    expect(find.text('html-view:$htmlBody'), findsOneWidget);
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

  testWidgets(
    'Trash detail restores selected message to INBOX and navigates back',
    (tester) async {
      final repository = _FakeMailboxRepository(thread: _trashThread);
      await tester.pumpWidget(
        _buildTestApp(
          repository: repository,
          initialMessageId: _trashThread.selectedMessageId,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete'), findsNothing);
      await tester.tap(find.byTooltip('Restore to INBOX'));
      await tester.pumpAndSettle();

      expect(repository.restoredMessageIds, [_trashMessage.id]);
      expect(find.text('Inbox route reached'), findsOneWidget);
    },
  );
}

Widget _buildTestApp({
  _FakeMailboxRepository? repository,
  String? initialMessageId,
  Widget Function(String html)? emailHtmlViewBuilder,
}) {
  final router = GoRouter(
    initialLocation: AppRoute.messageDetail.path.replaceFirst(
      ':id',
      initialMessageId ?? _thread.selectedMessageId,
    ),
    routes: [
      GoRoute(
        path: AppRoute.messageDetail.path,
        builder: (context, state) => MessageDetailScreen(
          messageId: state.pathParameters['id'] ?? '',
          emailHtmlViewBuilder: emailHtmlViewBuilder,
        ),
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

final _trashMessage = MailThreadMessage(
  id: 'avrcan@finestar.hr:trash:api:42',
  folderId: 'avrcan@finestar.hr:trash',
  folderName: 'Trash',
  subject: 'Trash restore smoke',
  sender: 'ante@vitalgroupsa.com',
  recipients: const ['avrcan@finestar.hr'],
  bodyPlain: 'Restore this message.',
  bodyHtml: null,
  receivedAt: DateTime(2026, 4, 16, 9),
  messageIdHeader: '<trash-message@finestar.hr>',
  inReplyToHeader: null,
  referencesHeader: null,
);

final _trashThread = MailThread(
  subject: 'Trash restore smoke',
  selectedMessageId: _trashMessage.id,
  messages: [_trashMessage],
);

class _FakeMailboxRepository implements MailboxRepository {
  _FakeMailboxRepository({MailThread? thread})
    : _currentThread = thread ?? _thread;

  final MailThread _currentThread;
  final markedReadMessageIds = <String>[];
  final deletedMessageIds = <String>[];
  final restoredMessageIds = <String>[];

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
  }) async => _currentThread;

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
  Future<MailRestoreResult> restoreMessagesToInbox({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async {
    restoredMessageIds.addAll(messageIds);
    return MailRestoreResult(restoredMessageIds: messageIds, failed: const []);
  }

  @override
  Future<MailRestoreResult> restoreMessageToInbox({
    required String accountId,
    required String messageId,
  }) async {
    restoredMessageIds.add(messageId);
    return MailRestoreResult(restoredMessageIds: [messageId], failed: const []);
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
