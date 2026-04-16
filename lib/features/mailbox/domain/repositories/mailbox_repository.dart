import '../entities/mail_folder.dart';
import '../entities/mail_message_detail.dart';
import '../entities/mail_message_summary.dart';

abstract class MailboxRepository {
  Future<List<MailFolder>> getFolders(String accountId);

  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
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

  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  });
}
