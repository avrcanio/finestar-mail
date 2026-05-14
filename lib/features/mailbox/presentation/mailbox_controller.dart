import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_delete_result.dart';
import '../domain/entities/mail_folder.dart';
import '../domain/entities/mail_conversation.dart';
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_page.dart';
import '../domain/entities/mail_message_summary.dart';
import '../domain/entities/mail_restore_result.dart';
import '../domain/entities/mail_thread.dart';

const Object _unchanged = Object();

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

final mailboxConversationsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<
      MailboxConversationsController,
      MailboxConversationsState,
      MailFolder
    >(MailboxConversationsController.new);

class MailboxConversationsState {
  const MailboxConversationsState({
    required this.conversations,
    this.hasMore = false,
    this.nextOffset = 0,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<MailConversation> conversations;
  final bool hasMore;
  final int nextOffset;
  final bool isLoadingMore;
  final String? loadMoreError;

  MailboxConversationsState copyWith({
    List<MailConversation>? conversations,
    bool? hasMore,
    int? nextOffset,
    bool? isLoadingMore,
    Object? loadMoreError = _unchanged,
  }) {
    return MailboxConversationsState(
      conversations: conversations ?? this.conversations,
      hasMore: hasMore ?? this.hasMore,
      nextOffset: nextOffset ?? this.nextOffset,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: loadMoreError == _unchanged
          ? this.loadMoreError
          : loadMoreError as String?,
    );
  }
}

class MailboxConversationsController
    extends AsyncNotifier<MailboxConversationsState> {
  MailboxConversationsController(this.folder);

  static const limit = 50;

  final MailFolder folder;

  @override
  Future<MailboxConversationsState> build() async {
    return _loadConversations(forceRefresh: true);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _loadConversations(forceRefresh: true),
    );
  }

  void removeMessagesFromState(Iterable<String> messageIds) {
    final current = state.asData?.value;
    final removedIds = messageIds.toSet();
    if (current == null || removedIds.isEmpty) {
      return;
    }

    state = AsyncData(
      current.copyWith(
        conversations: MailboxDeleteStateRemoval.removeFromConversations(
          current.conversations,
          removedIds,
        ),
      ),
    );
  }

  void applyMessageReadState(String messageId, bool isRead) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    var changed = false;
    final next = <MailConversation>[];
    for (final conversation in current.conversations) {
      final patched = MailboxDeleteStateRemoval.patchConversationReadState(
        conversation,
        messageId,
        isRead,
      );
      if (patched != null) {
        changed = true;
        next.add(patched);
      } else {
        next.add(conversation);
      }
    }
    if (!changed) {
      return;
    }
    state = AsyncData(current.copyWith(conversations: next));
  }

  Future<MailDeleteResult> moveSelectedToTrash(List<String> messageIds) async {
    final current = state.asData?.value;
    if (current == null || messageIds.isEmpty) {
      return const MailDeleteResult(movedMessageIds: [], failed: []);
    }

    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return MailDeleteResult(
        movedMessageIds: const [],
        failed: messageIds
            .map(
              (id) => MailDeleteFailure(
                messageId: id,
                message: 'Active account session is missing.',
              ),
            )
            .toList(),
      );
    }

    final repository = ref.read(mailboxRepositoryProvider);
    final results = <MailDeleteResult>[];
    for (final messageId in messageIds) {
      results.add(
        await repository.moveMessageToTrash(
          accountId: account.id,
          messageId: messageId,
        ),
      );
    }
    final result = MailDeleteResult(
      movedMessageIds: [
        for (final result in results) ...result.movedMessageIds,
      ],
      failed: [for (final result in results) ...result.failed],
    );
    removeMessagesFromState(result.movedMessageIds);
    return result;
  }

  Future<MailDeleteResult> moveSelectedToArchive(
    List<String> messageIds,
    String archivePath,
  ) async {
    final current = state.asData?.value;
    if (current == null || messageIds.isEmpty) {
      return const MailDeleteResult(movedMessageIds: [], failed: []);
    }

    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return MailDeleteResult(
        movedMessageIds: const [],
        failed: messageIds
            .map(
              (id) => MailDeleteFailure(
                messageId: id,
                message: 'Active account session is missing.',
              ),
            )
            .toList(),
      );
    }

    final repository = ref.read(mailboxRepositoryProvider);
    final results = <MailDeleteResult>[];
    for (final messageId in messageIds) {
      results.add(
        await repository.moveMessageToFolder(
          accountId: account.id,
          messageId: messageId,
          targetFolderPath: archivePath,
        ),
      );
    }
    final result = MailDeleteResult(
      movedMessageIds: [for (final r in results) ...r.movedMessageIds],
      failed: [for (final r in results) ...r.failed],
    );
    removeMessagesFromState(result.movedMessageIds);
    return result;
  }

  Future<MailRestoreResult> restoreSelectedToInbox(
    List<String> messageIds,
  ) async {
    final current = state.asData?.value;
    if (current == null || messageIds.isEmpty) {
      return const MailRestoreResult(restoredMessageIds: [], failed: []);
    }

    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return MailRestoreResult(
        restoredMessageIds: const [],
        failed: messageIds
            .map(
              (id) => MailRestoreFailure(
                messageId: id,
                message: 'Active account session is missing.',
              ),
            )
            .toList(),
      );
    }

    final repository = ref.read(mailboxRepositoryProvider);
    final results = <MailRestoreResult>[];
    for (final messageId in messageIds) {
      results.add(
        await repository.restoreMessageToInbox(
          accountId: account.id,
          messageId: messageId,
        ),
      );
    }
    final result = MailRestoreResult(
      restoredMessageIds: [
        for (final result in results) ...result.restoredMessageIds,
      ],
      failed: [for (final result in results) ...result.failed],
    );
    if (result.restoredMessageIds.isNotEmpty) {
      state = AsyncData(
        current.copyWith(
          conversations: MailboxDeleteStateRemoval.removeFromConversations(
            current.conversations,
            result.restoredMessageIds.toSet(),
          ),
        ),
      );
    }
    return result;
  }

  Future<MailboxConversationsState> _loadConversations({
    required bool forceRefresh,
  }) async {
    final account = await ref.watch(activeAccountProvider.future);
    if (account == null) {
      return const MailboxConversationsState(conversations: []);
    }

    final page = await ref
        .watch(mailboxRepositoryProvider)
        .getConversations(
          accountId: account.id,
          folder: folder,
          limit: limit,
          offset: 0,
          forceRefresh: forceRefresh,
        );
    return MailboxConversationsState(
      conversations: page.conversations,
      hasMore: page.hasMore,
      nextOffset: page.nextOffset,
    );
  }

  Future<void> loadMore() async {
    final asyncState = state;
    final current = asyncState.asData?.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
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
          .getConversations(
            accountId: account.id,
            folder: folder,
            limit: limit,
            offset: current.nextOffset,
            forceRefresh: false,
          );
      final existingIds = current.conversations.map((c) => c.id).toSet();
      final appended = page.conversations
          .where((c) => existingIds.add(c.id))
          .toList();
      state = AsyncData(
        current.copyWith(
          conversations: [...current.conversations, ...appended],
          hasMore: page.hasMore,
          nextOffset: page.nextOffset,
          isLoadingMore: false,
          loadMoreError: null,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error.toString()),
      );
    }
  }
}

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

  void removeMessagesFromState(Iterable<String> messageIds) {
    final current = state.asData?.value;
    final removedIds = messageIds.toSet();
    if (current == null || removedIds.isEmpty) {
      return;
    }

    state = AsyncData(
      current.copyWith(
        messages: MailboxDeleteStateRemoval.removeFromMessages(
          current.messages,
          removedIds,
        ),
      ),
    );
  }

  void applyMessageReadState(String messageId, bool isRead) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    var changed = false;
    final next = <MailMessageSummary>[];
    for (final message in current.messages) {
      if (message.id == messageId) {
        changed = true;
        next.add(message.copyWith(isRead: isRead));
      } else {
        next.add(message);
      }
    }
    if (!changed) {
      return;
    }
    state = AsyncData(current.copyWith(messages: next));
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

  Future<MailDeleteResult> moveSelectedToTrash(List<String> messageIds) async {
    final current = state.asData?.value;
    if (current == null || messageIds.isEmpty) {
      return const MailDeleteResult(movedMessageIds: [], failed: []);
    }

    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return MailDeleteResult(
        movedMessageIds: const [],
        failed: messageIds
            .map(
              (id) => MailDeleteFailure(
                messageId: id,
                message: 'Active account session is missing.',
              ),
            )
            .toList(),
      );
    }

    final result = await ref
        .read(mailboxRepositoryProvider)
        .moveMessagesToTrash(
          accountId: account.id,
          folder: folder,
          messageIds: messageIds,
        );
    removeMessagesFromState(result.movedMessageIds);
    return result;
  }

  Future<MailRestoreResult> restoreSelectedToInbox(
    List<String> messageIds,
  ) async {
    final current = state.asData?.value;
    if (current == null || messageIds.isEmpty) {
      return const MailRestoreResult(restoredMessageIds: [], failed: []);
    }

    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return MailRestoreResult(
        restoredMessageIds: const [],
        failed: messageIds
            .map(
              (id) => MailRestoreFailure(
                messageId: id,
                message: 'Active account session is missing.',
              ),
            )
            .toList(),
      );
    }

    final result = await ref
        .read(mailboxRepositoryProvider)
        .restoreMessagesToInbox(
          accountId: account.id,
          folder: folder,
          messageIds: messageIds,
        );
    if (result.restoredMessageIds.isNotEmpty) {
      final restoredIds = result.restoredMessageIds.toSet();
      state = AsyncData(
        current.copyWith(
          messages: current.messages
              .where((message) => !restoredIds.contains(message.id))
              .toList(),
        ),
      );
    }
    return result;
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

class MailboxDeleteStateRemoval {
  const MailboxDeleteStateRemoval._();

  static MailConversation? patchConversationReadState(
    MailConversation conversation,
    String messageId,
    bool isRead,
  ) {
    MailMessageSummary withRead(MailMessageSummary summary) {
      return summary.id == messageId
          ? summary.copyWith(isRead: isRead)
          : summary;
    }

    if (conversation.timelineMessages.isNotEmpty) {
      var touched = false;
      final newTimeline = <MailConversationMessage>[];
      for (final entry in conversation.timelineMessages) {
        if (entry.message.id == messageId) {
          touched = true;
          newTimeline.add(
            MailConversationMessage(
              message: entry.message.copyWith(isRead: isRead),
              direction: entry.direction,
            ),
          );
        } else {
          newTimeline.add(entry);
        }
      }
      if (!touched) {
        return null;
      }
      final hasUnread = newTimeline.any(
        (entry) =>
            entry.direction == MailConversationDirection.inbound &&
            !entry.message.isRead,
      );
      final newRoot = newTimeline.first.message;
      final newReplies =
          newTimeline.skip(1).map((entry) => entry.message).toList();
      return MailConversation(
        id: conversation.id,
        messageCount: conversation.messageCount,
        replyCount: conversation.replyCount,
        hasUnread: hasUnread,
        hasAttachments: conversation.hasAttachments,
        hasVisibleAttachments: conversation.hasVisibleAttachments,
        participants: conversation.participants,
        rootMessage: newRoot,
        replies: newReplies,
        latestDate: conversation.latestDate,
        timelineMessages: newTimeline,
      );
    }

    final rootTouched = conversation.rootMessage.id == messageId;
    final newRoot = withRead(conversation.rootMessage);
    final newReplies = conversation.replies.map(withRead).toList();
    final replyTouched = conversation.replies.any((r) => r.id == messageId);
    if (!rootTouched && !replyTouched) {
      return null;
    }
    final synthetic = <MailConversationMessage>[
      MailConversationMessage(
        message: newRoot,
        direction: MailConversationDirection.inbound,
      ),
      for (final reply in newReplies)
        MailConversationMessage(
          message: reply,
          direction: MailConversationDirection.inbound,
        ),
    ];
    final hasUnread = synthetic.any(
      (entry) =>
          entry.direction == MailConversationDirection.inbound &&
          !entry.message.isRead,
    );
    return MailConversation(
      id: conversation.id,
      messageCount: conversation.messageCount,
      replyCount: conversation.replyCount,
      hasUnread: hasUnread,
      hasAttachments: conversation.hasAttachments,
      hasVisibleAttachments: conversation.hasVisibleAttachments,
      participants: conversation.participants,
      rootMessage: newRoot,
      replies: newReplies,
      latestDate: conversation.latestDate,
    );
  }

  static List<MailMessageSummary> removeFromMessages(
    List<MailMessageSummary> messages,
    Set<String> messageIds,
  ) {
    if (messageIds.isEmpty) {
      return messages;
    }
    return messages
        .where((message) => !messageIds.contains(message.id))
        .toList();
  }

  static MailThread? removeFromThread(
    MailThread thread,
    Set<String> messageIds,
  ) {
    if (messageIds.isEmpty) {
      return thread;
    }
    final remainingMessages = thread.messages
        .where((message) => !messageIds.contains(message.id))
        .toList();
    if (remainingMessages.isEmpty) {
      return null;
    }
    final selectedMessageId =
        remainingMessages.any(
          (message) => message.id == thread.selectedMessageId,
        )
        ? thread.selectedMessageId
        : remainingMessages.first.id;
    return MailThread(
      subject: thread.subject,
      selectedMessageId: selectedMessageId,
      messages: remainingMessages,
    );
  }

  static List<MailConversation> removeFromConversations(
    List<MailConversation> conversations,
    Set<String> messageIds,
  ) {
    if (messageIds.isEmpty) {
      return conversations;
    }
    return conversations
        .map((conversation) {
          final remainingTimeline = conversation.messages
              .where((message) => !messageIds.contains(message.message.id))
              .toList();
          if (remainingTimeline.isEmpty) {
            return null;
          }
          final newRoot = remainingTimeline.first.message;
          final newReplies = remainingTimeline
              .skip(1)
              .map((message) => message.message)
              .toList();
          return MailConversation(
            id: conversation.id,
            messageCount: remainingTimeline.length,
            replyCount: newReplies.length,
            hasUnread:
                !newRoot.isRead || newReplies.any((reply) => !reply.isRead),
            hasAttachments:
                newRoot.hasAttachments ||
                newReplies.any((reply) => reply.hasAttachments),
            hasVisibleAttachments:
                newRoot.hasAttachments ||
                newReplies.any((reply) => reply.hasAttachments),
            participants: conversation.participants,
            rootMessage: newRoot,
            replies: newReplies,
            latestDate: newReplies.isEmpty
                ? newRoot.receivedAt
                : newReplies
                      .map((reply) => reply.receivedAt)
                      .fold(newRoot.receivedAt, _latestDate),
            timelineMessages: remainingTimeline,
          );
        })
        .whereType<MailConversation>()
        .toList();
  }

  static DateTime _latestDate(DateTime left, DateTime right) {
    return right.isAfter(left) ? right : left;
  }
}

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
