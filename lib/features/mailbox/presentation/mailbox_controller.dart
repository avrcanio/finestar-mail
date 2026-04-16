import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/entities/mail_folder.dart';
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_summary.dart';

final foldersProvider = FutureProvider<List<MailFolder>>((ref) {
  return ref.watch(mailboxRepositoryProvider).getFolders();
});

final inboxProvider =
    AsyncNotifierProvider.autoDispose<
      InboxController,
      List<MailMessageSummary>
    >(InboxController.new);

final messageDetailProvider = FutureProvider.family<MailMessageDetail, String>((
  ref,
  messageId,
) {
  return ref.watch(mailboxRepositoryProvider).getMessageDetail(messageId);
});

class InboxController extends AsyncNotifier<List<MailMessageSummary>> {
  @override
  Future<List<MailMessageSummary>> build() async {
    return ref.watch(mailboxRepositoryProvider).getInbox(forceRefresh: true);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.watch(mailboxRepositoryProvider).getInbox(forceRefresh: true),
    );
  }
}
