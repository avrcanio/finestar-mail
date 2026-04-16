import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_folder.dart';
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_summary.dart';
import '../domain/entities/mail_thread.dart';

final foldersProvider = FutureProvider<List<MailFolder>>((ref) {
  final account = ref.watch(activeAccountProvider).asData?.value;
  if (account == null) {
    return const [];
  }
  return ref.watch(mailboxRepositoryProvider).getFolders(account.id);
});

final messageDetailProvider = FutureProvider.family<MailMessageDetail, String>((
  ref,
  messageId,
) {
  final account = ref.watch(activeAccountProvider).asData?.value;
  if (account == null) {
    throw StateError('No active account selected.');
  }
  return ref
      .watch(mailboxRepositoryProvider)
      .getMessageDetail(accountId: account.id, id: messageId);
});

final messageThreadProvider = FutureProvider.family<MailThread, String>((
  ref,
  messageId,
) {
  final account = ref.watch(activeAccountProvider).asData?.value;
  if (account == null) {
    throw StateError('No active account selected.');
  }
  return ref
      .watch(mailboxRepositoryProvider)
      .getMessageThread(accountId: account.id, messageId: messageId);
});

final folderMessagesProvider = FutureProvider.autoDispose
    .family<List<MailMessageSummary>, MailFolder>((ref, folder) async {
      final account = await ref.watch(activeAccountProvider.future);
      if (account == null) {
        return const [];
      }

      return ref
          .watch(mailboxRepositoryProvider)
          .getMessages(
            accountId: account.id,
            folder: folder,
            forceRefresh: true,
          );
    });

final mailboxSearchProvider = FutureProvider.autoDispose
    .family<List<MailMessageSummary>, MailboxSearchRequest>((
      ref,
      request,
    ) async {
      final normalizedQuery = request.query.trim();
      if (normalizedQuery.isEmpty) {
        return const [];
      }

      final account = await ref.watch(activeAccountProvider.future);
      if (account == null) {
        return const [];
      }

      return ref
          .watch(mailboxRepositoryProvider)
          .searchMessages(
            accountId: account.id,
            folder: request.folder,
            query: normalizedQuery,
          );
    });

class MailboxSearchRequest {
  const MailboxSearchRequest({required this.folder, required this.query});

  final MailFolder folder;
  final String query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MailboxSearchRequest &&
          other.folder.id == folder.id &&
          other.query == query;

  @override
  int get hashCode => Object.hash(folder.id, query);
}
