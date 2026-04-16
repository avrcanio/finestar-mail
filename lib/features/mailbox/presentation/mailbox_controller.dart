import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_folder.dart';
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_page.dart';
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

final mailboxMessagesControllerProvider = AsyncNotifierProvider.autoDispose
    .family<MailboxMessagesController, MailboxMessagesState, MailFolder>(
      MailboxMessagesController.new,
    );

final folderMessagesProvider = FutureProvider.autoDispose
    .family<List<MailMessageSummary>, MailFolder>((ref, folder) async {
      final page = await ref.watch(
        mailboxMessagesControllerProvider(folder).future,
      );
      return page.messages;
    });

class MailboxMessagesState {
  const MailboxMessagesState({
    required this.messages,
    required this.hasMore,
    this.nextBeforeUid,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<MailMessageSummary> messages;
  final bool hasMore;
  final String? nextBeforeUid;
  final bool isLoadingMore;
  final String? loadMoreError;

  MailboxMessagesState copyWith({
    List<MailMessageSummary>? messages,
    bool? hasMore,
    Object? nextBeforeUid = _unchanged,
    bool? isLoadingMore,
    Object? loadMoreError = _unchanged,
  }) {
    return MailboxMessagesState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      nextBeforeUid: nextBeforeUid == _unchanged
          ? this.nextBeforeUid
          : nextBeforeUid as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: loadMoreError == _unchanged
          ? this.loadMoreError
          : loadMoreError as String?,
    );
  }
}

class MailboxMessagesController extends AsyncNotifier<MailboxMessagesState> {
  MailboxMessagesController(this.folder);

  static const pageSize = 50;

  final MailFolder folder;

  @override
  Future<MailboxMessagesState> build() {
    return _loadFirstPage(folder);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadFirstPage(folder));
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null ||
        current.isLoadingMore ||
        !current.hasMore ||
        current.nextBeforeUid == null) {
      return;
    }

    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreError: null),
    );

    try {
      final account = await ref.read(activeAccountProvider.future);
      if (account == null) {
        state = AsyncData(
          current.copyWith(isLoadingMore: false, loadMoreError: null),
        );
        return;
      }

      final page = await ref
          .read(mailboxRepositoryProvider)
          .getMessagePage(
            accountId: account.id,
            folder: folder,
            pageSize: pageSize,
            beforeUid: current.nextBeforeUid,
          );
      state = AsyncData(_appendPage(current, page));
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error.toString()),
      );
    }
  }

  Future<MailboxMessagesState> _loadFirstPage(MailFolder folder) async {
    final account = await ref.watch(activeAccountProvider.future);
    if (account == null) {
      return const MailboxMessagesState(messages: [], hasMore: false);
    }

    final page = await ref
        .watch(mailboxRepositoryProvider)
        .getMessagePage(
          accountId: account.id,
          folder: folder,
          pageSize: pageSize,
          forceRefresh: true,
        );
    return MailboxMessagesState(
      messages: page.messages,
      hasMore: page.hasMore,
      nextBeforeUid: page.nextBeforeUid,
    );
  }

  MailboxMessagesState _appendPage(
    MailboxMessagesState current,
    MailMessagePage page,
  ) {
    final existingIds = current.messages.map((message) => message.id).toSet();
    final appended = page.messages
        .where((message) => existingIds.add(message.id))
        .toList();
    return MailboxMessagesState(
      messages: [...current.messages, ...appended],
      hasMore: page.hasMore,
      nextBeforeUid: page.nextBeforeUid,
    );
  }
}

const Object _unchanged = Object();

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
