import '../entities/attachment_ref.dart';

abstract class AttachmentRepository {
  Future<List<AttachmentRef>> pickAttachments();
}
