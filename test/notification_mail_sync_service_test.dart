import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_delete_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_conversation.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_attachment.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_detail.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_page.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_message_summary.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_restore_result.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_thread.dart';
import 'package:finestar_mail/features/mailbox/domain/repositories/mailbox_repository.dart';
import 'package:finestar_mail/features/notifications/data/mail_notification_payload.dart';
import 'package:finestar_mail/features/notifications/data/notification_mail_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncInboxForPayload syncs inbox for active account', () async {
    final repository = _FakeMailboxRepository();
    final service = NotificationMailSyncService(
      activeAccountLoader: () async => _account,
      mailboxRepository: repository,
    );

    final synced = await service.syncInboxForPayload(
      const MailNotificationPayload(accountEmail: 'avrcan@finestar.hr'),
    );

    expect(synced, isTrue);
    expect(repository.syncedAccountIds, ['avrcan@finestar.hr']);
    expect(repository.forceRefreshValues, [true]);
  });

  test(
    'syncInboxForPayload ignores notifications for another account',
    () async {
      final repository = _FakeMailboxRepository();
      final service = NotificationMailSyncService(
        activeAccountLoader: () async => _account,
        mailboxRepository: repository,
      );

      final synced = await service.syncInboxForPayload(
        const MailNotificationPayload(accountEmail: 'other@finestar.hr'),
      );

      expect(synced, isFalse);
      expect(repository.syncedAccountIds, isEmpty);
    },
  );

  test('syncInboxForPayload does not crash when no account exists', () async {
    final repository = _FakeMailboxRepository();
    final service = NotificationMailSyncService(
      activeAccountLoader: () async => null,
      mailboxRepository: repository,
    );

    final synced = await service.syncInboxForPayload(
      const MailNotificationPayload(subject: 'New mail'),
    );

    expect(synced, isFalse);
    expect(repository.syncedAccountIds, isEmpty);
  });

  test('syncInboxForPayload returns false when sync fails', () async {
    final repository = _FakeMailboxRepository(throwOnSync: true);
    final service = NotificationMailSyncService(
      activeAccountLoader: () async => _account,
      mailboxRepository: repository,
    );

    final synced = await service.syncInboxForPayload(
      const MailNotificationPayload(subject: 'New mail'),
    );

    expect(synced, isFalse);
    expect(repository.syncedAccountIds, ['avrcan@finestar.hr']);
  });
}

final _account = MailAccount(
  id: 'avrcan@finestar.hr',
  email: 'avrcan@finestar.hr',
  displayName: 'Ante Vrcan',
  connectionSettings: const ConnectionSettings(
    imapHost: 'mail.finestar.hr',
    imapPort: 993,
    imapSecurity: MailSecurity.sslTls,
    smtpHost: 'mail.finestar.hr',
    smtpPort: 465,
    smtpSecurity: MailSecurity.sslTls,
  ),
  createdAt: DateTime(2026, 4, 16),
);

class _FakeMailboxRepository implements MailboxRepository {
  _FakeMailboxRepository({this.throwOnSync = false});

  final bool throwOnSync;
  final syncedAccountIds = <String>[];
  final forceRefreshValues = <bool>[];

  @override
  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    syncedAccountIds.add(accountId);
    forceRefreshValues.add(forceRefresh);
    if (throwOnSync) {
      throw StateError('sync failed');
    }
    return const [];
  }

  @override
  Future<List<MailConversation>> getUnifiedConversations({
    required String accountId,
    int limit = 50,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<String?> findCachedMessageId({
    required String accountId,
    String? localMessageId,
    String? folder,
    String? uid,
    String? rfcMessageId,
    String? subject,
    String? sender,
  }) async => localMessageId;

  @override
  Future<void> setMessageRead({
    required String accountId,
    required String messageId,
    required bool isRead,
  }) async {}

  @override
  Future<void> setMessageImportant({
    required String accountId,
    required String messageId,
    required bool isImportant,
  }) async {}

  @override
  Future<void> setMessagePinned({
    required String accountId,
    required String messageId,
    required bool isPinned,
  }) async {}

  @override
  Future<List<MailFolder>> getFolders(String accountId) async => const [];

  @override
  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
    bool forceRefresh = false,
  }) async => const MailMessagePage(messages: [], hasMore: false);

  @override
  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DownloadedMailAttachment> downloadAttachment({
    required String accountId,
    required String messageId,
    required MailMessageAttachment attachment,
  }) async => const DownloadedMailAttachment(
    filename: 'attachment.txt',
    contentType: 'text/plain',
    bytes: [104, 105],
  );

  @override
  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MailDeleteResult> moveMessagesToTrash({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async => const MailDeleteResult(movedMessageIds: [], failed: []);

  @override
  Future<MailDeleteResult> moveMessageToTrash({
    required String accountId,
    required String messageId,
  }) async => const MailDeleteResult(movedMessageIds: [], failed: []);

  @override
  Future<MailRestoreResult> restoreMessagesToInbox({
    required String accountId,
    required MailFolder folder,
    required List<String> messageIds,
  }) async => const MailRestoreResult(restoredMessageIds: [], failed: []);

  @override
  Future<MailRestoreResult> restoreMessageToInbox({
    required String accountId,
    required String messageId,
  }) async => const MailRestoreResult(restoredMessageIds: [], failed: []);

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required MailFolder folder,
    required String query,
    int limit = 30,
  }) async => const [];
}
