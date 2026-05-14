import 'entities/mail_conversation.dart';
import 'entities/mail_folder.dart';

/// Returns the IMAP `path` of a selectable folder that should receive archived
/// mail, or `null` if none is found.
String? selectableArchiveFolderPath(Iterable<MailFolder> folders) {
  final selectable = folders.where((f) => f.selectable).toList();
  if (selectable.isEmpty) {
    return null;
  }

  for (final folder in selectable) {
    if (folder.path.trim().toLowerCase() == 'archive') {
      return folder.path.trim();
    }
  }

  final candidates = <MailFolder>[];
  for (final folder in selectable) {
    final path = folder.path.trim().toLowerCase();
    final name = folder.name.trim().toLowerCase();
    if (name == 'archive' ||
        path.endsWith('/archive') ||
        path.endsWith('.archive')) {
      candidates.add(folder);
    }
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) => a.path.length.compareTo(b.path.length));
  return candidates.first.path.trim();
}

/// Whether an IMAP folder path/name refers to an Archive mailbox.
bool isArchiveFolderPath(String folderPath, String folderName) {
  final path = folderPath.trim().toLowerCase();
  final name = folderName.trim().toLowerCase();
  if (path == 'archive' || name == 'archive') {
    return true;
  }
  return path.endsWith('/archive') || path.endsWith('.archive');
}

/// Whether [folder] is treated as the Archive mailbox (for hiding archive UI).
bool isArchiveLikeFolder(MailFolder folder) {
  if (!folder.selectable) {
    return false;
  }
  return isArchiveFolderPath(folder.path, folder.name);
}

/// Message rows in this folder should be offered for archive swipe / bulk archive.
Iterable<String> messageIdsInConversationForFolder(
  MailConversation conversation,
  MailFolder folder,
) sync* {
  for (final item in conversation.messages) {
    if (item.message.folderId == folder.id) {
      yield item.message.id;
    }
  }
}
