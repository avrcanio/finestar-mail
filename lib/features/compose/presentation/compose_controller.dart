import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/result.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/reply_context.dart';
import '../domain/entities/outgoing_message.dart';

final composeControllerProvider =
    AsyncNotifierProvider.autoDispose<ComposeController, List<AttachmentRef>>(
      ComposeController.new,
    );

class ComposeController extends AsyncNotifier<List<AttachmentRef>> {
  @override
  Future<List<AttachmentRef>> build() async => const [];

  Future<void> pickAttachments() async {
    await pickFiles();
  }

  Future<void> pickFiles() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .pickFiles();
    _appendAttachments(currentAttachments, attachments);
  }

  Future<void> pickPhotos() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .pickPhotos();
    _appendAttachments(currentAttachments, attachments);
  }

  Future<void> takePhoto() async {
    final currentAttachments = state.asData?.value ?? const [];
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .takePhoto();
    _appendAttachments(currentAttachments, attachments);
  }

  void removeAttachment(String id) {
    final attachments = state.asData?.value ?? const [];
    state = AsyncData(
      attachments.where((attachment) => attachment.id != id).toList(),
    );
  }

  void _appendAttachments(
    List<AttachmentRef> currentAttachments,
    List<AttachmentRef> attachments,
  ) {
    state = AsyncData([...currentAttachments, ...attachments]);
  }

  Future<Result<void>> send({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    ReplyContext? replyContext,
  }) async {
    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return const Failure<void>('Add an account before sending mail.');
    }

    final message = OutgoingMessage(
      accountId: account.id,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: state.asData?.value ?? const [],
      replyContext: replyContext,
    );
    return ref.watch(composeRepositoryProvider).send(message);
  }
}
