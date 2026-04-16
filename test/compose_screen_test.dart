import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/features/attachments/domain/entities/attachment_ref.dart';
import 'package:finestar_mail/features/attachments/domain/repositories/attachment_repository.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/presentation/auth_controller.dart';
import 'package:finestar_mail/features/compose/domain/entities/outgoing_message.dart';
import 'package:finestar_mail/features/compose/domain/entities/reply_context.dart';
import 'package:finestar_mail/features/compose/domain/repositories/compose_repository.dart';
import 'package:finestar_mail/features/compose/presentation/compose_controller.dart';
import 'package:finestar_mail/features/compose/presentation/compose_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compose screen shows Gmail-like toolbar and fields', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Attach'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('More options'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text(_account.email), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Compose email'), findsOneWidget);
    expect(find.text('Cc'), findsNothing);
    expect(find.text('Bcc'), findsNothing);
  });

  testWidgets('attachment menu shows Gmail-like options', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();

    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);
  });

  testWidgets('more menu shows Gmail-like options', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Schedule send'), findsOneWidget);
    expect(find.text('Add from Contacts'), findsOneWidget);
    expect(find.text('Confidential mode'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help & feedback'), findsOneWidget);
  });

  testWidgets('cc and bcc rows are revealed from chevron', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show Cc and Bcc'));
    await tester.pumpAndSettle();

    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Bcc'), findsOneWidget);
  });

  testWidgets('reply context prefills recipients, subject, and quoted text', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(replyContext: _replyContext));
    await tester.pumpAndSettle();

    expect(find.text('client@finestar.hr'), findsOneWidget);
    expect(find.text('Re: Project update'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.controller.text.contains('On Thu, Apr 16, 2026') &&
            widget.controller.text.contains('> Original body'),
      ),
      findsOneWidget,
    );
  });

  test('compose controller adds, removes, and sends attachments', () async {
    final composeRepository = _FakeComposeRepository();
    final container = ProviderContainer(
      overrides: [
        activeAccountProvider.overrideWith((ref) async => _account),
        attachmentRepositoryProvider.overrideWith(
          (ref) => _FakeAttachmentRepository(),
        ),
        composeRepositoryProvider.overrideWith((ref) => composeRepository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(composeControllerProvider.future);
    final controller = container.read(composeControllerProvider.notifier);

    await controller.pickFiles();
    expect(
      container.read(composeControllerProvider).value?.single.fileName,
      'proposal.pdf',
    );

    controller.removeAttachment('file-1');
    expect(container.read(composeControllerProvider).value, isEmpty);

    await controller.pickPhotos();
    await controller.send(
      to: const ['client@finestar.hr'],
      cc: const [],
      bcc: const [],
      subject: 'Photo',
      body: 'Attached.',
      replyContext: _replyContext,
    );

    expect(
      composeRepository.lastMessage?.attachments.single.fileName,
      'photo.jpg',
    );
    expect(composeRepository.lastMessage?.replyContext?.targetMessageId, 'm1');
  });
}

Widget _buildTestApp({ReplyContext? replyContext}) {
  return ProviderScope(
    overrides: [
      activeAccountProvider.overrideWith((ref) async => _account),
      attachmentRepositoryProvider.overrideWith(
        (ref) => _FakeAttachmentRepository(),
      ),
      composeRepositoryProvider.overrideWith((ref) => _FakeComposeRepository()),
    ],
    child: MaterialApp(home: ComposeScreen(replyContext: replyContext)),
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

final _replyContext = ReplyContext(
  messageId: 'thread-root',
  targetMessageId: 'm1',
  subject: 'Project update',
  action: ReplyAction.reply,
  recipients: const ['client@finestar.hr'],
  originalSender: 'client@finestar.hr',
  originalReceivedAt: DateTime(2026, 4, 16, 8, 30),
  originalBody: 'Original body',
  originalMessageIdHeader: '<m1@finestar.hr>',
  originalReferencesHeader: '<root@finestar.hr>',
);

class _FakeAttachmentRepository implements AttachmentRepository {
  @override
  Future<List<AttachmentRef>> pickAttachments() => pickFiles();

  @override
  Future<List<AttachmentRef>> pickFiles() async => const [
    AttachmentRef(
      id: 'file-1',
      fileName: 'proposal.pdf',
      filePath: '/tmp/proposal.pdf',
      sizeBytes: 42,
      mimeType: 'application/pdf',
    ),
  ];

  @override
  Future<List<AttachmentRef>> pickPhotos() async => const [
    AttachmentRef(
      id: 'photo-1',
      fileName: 'photo.jpg',
      filePath: '/tmp/photo.jpg',
      sizeBytes: 84,
      mimeType: 'image/jpeg',
    ),
  ];

  @override
  Future<List<AttachmentRef>> takePhoto() async => const [
    AttachmentRef(
      id: 'camera-1',
      fileName: 'camera.jpg',
      filePath: '/tmp/camera.jpg',
      sizeBytes: 126,
      mimeType: 'image/jpeg',
    ),
  ];
}

class _FakeComposeRepository implements ComposeRepository {
  OutgoingMessage? lastMessage;

  @override
  Future<Result<void>> send(OutgoingMessage message) async {
    lastMessage = message;
    return const Success(null);
  }
}
