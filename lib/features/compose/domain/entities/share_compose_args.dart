import '../../../attachments/domain/entities/attachment_ref.dart';

class ShareComposeArgs {
  const ShareComposeArgs({
    required this.accountId,
    required this.fromEmail,
    required this.attachments,
  });

  final String accountId;
  final String fromEmail;
  final List<AttachmentRef> attachments;
}

