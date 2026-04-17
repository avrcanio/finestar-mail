import '../../../attachments/domain/entities/attachment_ref.dart';

sealed class ComposeAttachment {
  const ComposeAttachment({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String id;
  final String fileName;
  final int? sizeBytes;
  final String mimeType;
}

class LocalComposeAttachment extends ComposeAttachment {
  LocalComposeAttachment({required this.attachment})
    : super(
        id: 'local:${attachment.id}',
        fileName: attachment.fileName,
        sizeBytes: attachment.sizeBytes,
        mimeType: attachment.mimeType,
      );

  final AttachmentRef attachment;
}

class ForwardedComposeAttachment extends ComposeAttachment {
  const ForwardedComposeAttachment({
    required this.attachmentId,
    required super.fileName,
    required super.sizeBytes,
    required super.mimeType,
  }) : super(id: 'forwarded:$attachmentId');

  final String attachmentId;
}
