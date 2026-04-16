import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/entities/attachment_ref.dart';
import '../domain/repositories/attachment_repository.dart';

class AttachmentRepositoryImpl implements AttachmentRepository {
  AttachmentRepositoryImpl({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  Future<List<AttachmentRef>> pickAttachments() => pickFiles();

  @override
  Future<List<AttachmentRef>> pickFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null) {
      return const [];
    }

    return result.files
        .where((file) => file.path != null)
        .map(
          (file) => AttachmentRef(
            id: _attachmentId(file.path!),
            fileName: file.name,
            filePath: file.path!,
            sizeBytes: file.size,
            mimeType: _mimeType(file.extension),
          ),
        )
        .toList();
  }

  @override
  Future<List<AttachmentRef>> pickPhotos() async {
    final photos = await _imagePicker.pickMultiImage();
    return Future.wait(photos.map(_attachmentFromXFile));
  }

  @override
  Future<List<AttachmentRef>> takePhoto() async {
    final photo = await _imagePicker.pickImage(source: ImageSource.camera);
    if (photo == null) {
      return const [];
    }
    return [await _attachmentFromXFile(photo)];
  }

  Future<AttachmentRef> _attachmentFromXFile(XFile file) async {
    final length = await file.length();
    return AttachmentRef(
      id: _attachmentId(file.path),
      fileName: file.name,
      filePath: file.path,
      sizeBytes: length,
      mimeType: file.mimeType ?? _mimeType(file.path.split('.').last),
    );
  }

  String _attachmentId(String path) =>
      '${DateTime.now().microsecondsSinceEpoch}:${path.hashCode}';

  String _mimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
