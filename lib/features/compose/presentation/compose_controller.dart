import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/result.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
import '../../auth/domain/entities/mail_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/compose_attachment.dart';
import '../domain/entities/reply_context.dart';
import '../domain/entities/outgoing_message.dart';

final composeControllerProvider =
    AsyncNotifierProvider.autoDispose<
      ComposeController,
      List<ComposeAttachment>
    >(ComposeController.new);

class ComposeController extends AsyncNotifier<List<ComposeAttachment>> {
  @override
  Future<List<ComposeAttachment>> build() async => const [];

  void setForwardedAttachments(List<ForwardedAttachmentRef> attachments) {
    final currentAttachments = state.asData?.value ?? const [];
    final localAttachments = currentAttachments
        .whereType<LocalComposeAttachment>()
        .toList();
    state = AsyncData([
      ...attachments.map(
        (attachment) => ForwardedComposeAttachment(
          attachmentId: attachment.attachmentId,
          fileName: attachment.fileName,
          sizeBytes: attachment.sizeBytes,
          mimeType: attachment.mimeType,
        ),
      ),
      ...localAttachments,
    ]);
  }

  Future<void> pickAttachments() async {
    await pickFiles();
  }

  Future<void> pickFiles() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .pickFiles();
    _appendLocalAttachments(currentAttachments, attachments);
  }

  Future<void> pickPhotos() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .pickPhotos();
    _appendLocalAttachments(currentAttachments, attachments);
  }

  Future<void> takePhoto() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .takePhoto();
    _appendLocalAttachments(currentAttachments, attachments);
  }

  void removeAttachment(String id) {
    final attachments = state.asData?.value ?? const [];
    state = AsyncData(
      attachments
          .where((attachment) => !_attachmentMatchesId(attachment, id))
          .toList(),
    );
  }

  bool _attachmentMatchesId(ComposeAttachment attachment, String id) {
    if (attachment.id == id) {
      return true;
    }
    return switch (attachment) {
      LocalComposeAttachment(:final attachment) => attachment.id == id,
      ForwardedComposeAttachment(:final attachmentId) => attachmentId == id,
    };
  }

  void _appendLocalAttachments(
    List<ComposeAttachment> currentAttachments,
    List<AttachmentRef> attachments,
  ) {
    state = AsyncData([
      ...currentAttachments,
      ...attachments.map(
        (attachment) => LocalComposeAttachment(attachment: attachment),
      ),
    ]);
  }

  void addLocalAttachments(List<AttachmentRef> attachments) {
    if (attachments.isEmpty) {
      return;
    }
    final currentAttachments = state.asData?.value ?? const [];
    _appendLocalAttachments(currentAttachments, attachments);
  }

  Future<Result<void>> send({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    ReplyContext? replyContext,
    String? accountIdOverride,
  }) async {
    final account = accountIdOverride == null
        ? await ref.read(activeAccountProvider.future)
        : await _loadAccount(accountIdOverride);
    if (account == null) {
      return const Failure<void>('Add an account before sending mail.');
    }
    final attachments = state.asData?.value ?? const [];
    final localAttachments = attachments
        .whereType<LocalComposeAttachment>()
        .map((attachment) => attachment.attachment)
        .toList();
    final forwardedAttachmentIds = attachments
        .whereType<ForwardedComposeAttachment>()
        .map((attachment) => attachment.attachmentId)
        .toList();
    final sourceFolder = replyContext?.forwardSourceFolder?.trim();
    final sourceUid = replyContext?.forwardSourceUid?.trim();
    final forwardSourceMessage =
        replyContext?.action == ReplyAction.forward &&
            forwardedAttachmentIds.isNotEmpty &&
            sourceFolder != null &&
            sourceFolder.isNotEmpty &&
            sourceUid != null &&
            sourceUid.isNotEmpty
        ? ForwardSourceMessage(
            folder: sourceFolder,
            uid: sourceUid,
            attachmentIds: forwardedAttachmentIds,
          )
        : null;

    final message = OutgoingMessage(
      accountId: account.id,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: localAttachments,
      replyContext: replyContext,
      forwardSourceMessage: forwardSourceMessage,
    );
    return ref.watch(composeRepositoryProvider).send(message);
  }

  Future<MailAccount?> _loadAccount(String accountId) async {
    final accounts = await ref.read(accountsProvider.future);
    for (final account in accounts) {
      if (account.id == accountId) {
        return account;
      }
    }
    return null;
  }
}
