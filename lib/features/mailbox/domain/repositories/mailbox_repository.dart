import '../entities/mail_folder.dart';
import '../entities/mail_message_detail.dart';
import '../entities/mail_message_summary.dart';

abstract class MailboxRepository {
  Future<List<MailFolder>> getFolders();

  Future<List<MailMessageSummary>> getInbox({
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  });

  Future<MailMessageDetail> getMessageDetail(String id);
}
