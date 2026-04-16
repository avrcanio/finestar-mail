import '../entities/attachment_ref.dart';

abstract class AttachmentRepository {
  Future<List<AttachmentRef>> pickAttachments();

  Future<List<AttachmentRef>> pickFiles();

  Future<List<AttachmentRef>> pickPhotos();

  Future<List<AttachmentRef>> takePhoto();
}
