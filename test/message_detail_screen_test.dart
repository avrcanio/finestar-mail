import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/core/theme/app_theme.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/compose/domain/entities/reply_context.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/repositories/mailbox_repository.dart';
import 'package:finestar_mail/features/mailbox/presentation/message_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('message detail renders main-screen content', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_message.subject), findsOneWidget);
    expect(
      find.textContaining(_message.sender, findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(_message.recipients.single, findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Apr 16, 2026 05:19'), findsOneWidget);
    expect(find.text(_message.bodyPlain), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Reply all'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);

    final actionRow = tester.widget<Row>(
      find
          .ancestor(of: find.text('Reply all'), matching: find.byType(Row))
          .last,
    );
    expect(actionRow.children.whereType<Expanded>(), hasLength(3));
  });

  testWidgets('reply actions navigate with correct reply context', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('reply:${_message.sender}'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply all'));
    await tester.pumpAndSettle();
    expect(
      find.text('replyAll:${_message.sender},${_message.recipients.single}'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    expect(find.text('forward:'), findsOneWidget);
  });
}

Widget _buildTestApp() {
  final router = GoRouter(
    initialLocation: AppRoute.messageDetail.path.replaceFirst(
      ':id',
      _message.id,
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
              '${replyContext.action.name}:${replyContext.recipients.join(',')}',
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
      mailboxRepositoryProvider.overrideWith((ref) => _FakeMailboxRepository()),
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

final _message = MailMessageDetail(
  id: 'message-1',
  subject: 'Re: test',
  sender: 'ante@vitalgroupsa.com',
  recipients: const ['avrcan@finestar.hr'],
  bodyPlain: 'ok\n\nOn 16/04/2026 05:17, Ante Vrcan wrote:\n> test proba',
  bodyHtml: null,
  receivedAt: DateTime(2026, 4, 16, 5, 19),
);

class _FakeMailboxRepository implements MailboxRepository {
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
  }) async => _message;

  @override
  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  }) async => const [];
}
