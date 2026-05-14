import '../entities/mail_folder.dart';
import '../entities/mail_conversation.dart';
import '../entities/mail_conversations_page.dart';
import '../entities/mail_delete_result.dart';
import '../entities/mail_message_detail.dart';
import '../entities/mail_message_attachment.dart';
import '../entities/mail_message_page.dart';
import '../entities/mail_message_summary.dart';
import '../entities/mail_restore_result.dart';
import '../entities/mail_thread.dart';
import '../entities/mail_message_translation.dart';

abstract class MailboxRepository {
  Future<List<MailFolder>> getFolders(String accountId);

  /// Paths from the last successful backend `GET /api/mail/folders` response (MRU order).
  /// Empty until [getFolders] has completed a remote fetch for this [accountId].
  List<String> getRecentMoveDestinationPaths(String accountId);

  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  });

  Future<MailConversationsPage> getConversations({
    required String accountId,
    required MailFolder folder,
    int limit = 50,
    int offset = 0,
    bool forceRefresh = false,
  });

  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
    bool forceRefresh = false,
  });

  Future<List<MailConversation>> getUnifiedConversations({
    required String accountId,
    int limit = 50,
    bool forceRefresh = false,
  });

  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  });

  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  });

  Future<DownloadedMailAttachment> downloadAttachment({
    required String accountId,
    required String messageId,
    required MailMessageAttachment attachment,
  });

  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
  });

  Future<MailMessageTranslation> translateMessage({
    required String accountId,
    required String messageId,
    required String targetLanguage,
  });

  Future<MailDeleteResult> moveMessagesToTrash({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  });

  Future<MailDeleteResult> moveMessageToTrash({
    required String accountId,
    required String messageId,
  });

  Future<MailDeleteResult> moveMessageToFolder({
    required String accountId,
    required String messageId,
    required String targetFolderPath,
  });

  Future<MailRestoreResult> restoreMessagesToInbox({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  });

  Future<MailRestoreResult> restoreMessageToInbox({
    required String accountId,
    required String messageId,
  });

  Future<String?> findCachedMessageId({
    required String accountId,
    String? localMessageId,
    String? folder,
    String? uid,
    String? rfcMessageId,
    String? subject,
    String? sender,
  });

  Future<void> setMessageRead({
    required String accountId,
    required String messageId,
    required bool isRead,
  });

  Future<void> setMessageImportant({
    required String accountId,
    required String messageId,
    required bool isImportant,
  });

  Future<void> setMessagePinned({
    required String accountId,
    required String messageId,
    required bool isPinned,
  });

  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  });
}
