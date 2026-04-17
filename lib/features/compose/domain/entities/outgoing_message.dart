import '../../../attachments/domain/entities/attachment_ref.dart';
import 'reply_context.dart';

class ForwardSourceMessage {
  const ForwardSourceMessage({
    required this.folder,
    required this.uid,
    required this.attachmentIds,
  });

  final String folder;
  final String uid;
  final List<String> attachmentIds;
}

class OutgoingMessage {
  const OutgoingMessage({
    required this.accountId,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.body,
    required this.attachments,
    this.replyContext,
    this.forwardSourceMessage,
  });

  final String accountId;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;
  final List<AttachmentRef> attachments;
  final ReplyContext? replyContext;
  final ForwardSourceMessage? forwardSourceMessage;
}
