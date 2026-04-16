import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/result.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
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
    state = const AsyncLoading();
    final attachments = await ref
        .watch(attachmentRepositoryProvider)
        .pickAttachments();
    state = AsyncData(attachments);
  }

  Future<Result<void>> send({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    ReplyContext? replyContext,
  }) async {
    final message = OutgoingMessage(
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
