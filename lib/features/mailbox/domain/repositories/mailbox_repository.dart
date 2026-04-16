import '../entities/mail_folder.dart';
import '../entities/mail_delete_result.dart';
import '../entities/mail_message_detail.dart';
import '../entities/mail_message_page.dart';
import '../entities/mail_message_summary.dart';
import '../entities/mail_thread.dart';

abstract class MailboxRepository {
  Future<List<MailFolder>> getFolders(String accountId);

  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  });

  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
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

  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
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
