import '../domain/entities/attachment_ref.dart';
import '../domain/repositories/attachment_repository.dart';

class AttachmentRepositoryImpl implements AttachmentRepository {
  @override
  Future<List<AttachmentRef>> pickAttachments() async => const [];
}
