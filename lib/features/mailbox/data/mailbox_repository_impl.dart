import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/entities/mail_folder.dart' as domain;
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_summary.dart';
import '../domain/repositories/mailbox_repository.dart';

class MailboxRepositoryImpl implements MailboxRepository {
  MailboxRepositoryImpl({required db.AppDatabase appDatabase})
    : _appDatabase = appDatabase;

  final db.AppDatabase _appDatabase;

  static const _seedFolders = [
    domain.MailFolder(id: 'inbox', name: 'Inbox', path: 'INBOX', isInbox: true),
    domain.MailFolder(id: 'sent', name: 'Sent', path: 'Sent', isInbox: false),
    domain.MailFolder(
      id: 'archive',
      name: 'Archive',
      path: 'Archive',
      isInbox: false,
    ),
  ];

  static final _seedMessages = List.generate(
    12,
    (index) => MailMessageSummary(
      id: 'msg_$index',
      folderId: 'inbox',
      subject: 'Sprint ${index + 1} status update',
      sender: index.isEven ? 'team@finestar.dev' : 'founder@finestar.dev',
      preview: 'This is a cached preview for message ${index + 1}.',
      receivedAt: DateTime.now().subtract(Duration(hours: index * 3)),
      isRead: index > 3,
      hasAttachments: index % 3 == 0,
      sequence: index,
    ),
  );

  @override
  Future<List<domain.MailFolder>> getFolders() async {
    await _appDatabase.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _appDatabase.mailFolders,
        _seedFolders
            .map(
              (folder) => db.MailFoldersCompanion.insert(
                id: folder.id,
                accountId: 'default',
                name: folder.name,
                path: folder.path,
                isInbox: folder.isInbox,
              ),
            )
            .toList(),
      );
    });

    final rows = await _appDatabase.select(_appDatabase.mailFolders).get();
    return rows
        .map(
          (row) => domain.MailFolder(
            id: row.id,
            name: row.name,
            path: row.path,
            isInbox: row.isInbox,
          ),
        )
        .toList();
  }

  @override
  Future<List<MailMessageSummary>> getInbox({
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      await _cacheSeedMessages();
    }

    final cached =
        await (_appDatabase.select(_appDatabase.messageSummaries)
              ..where((table) => table.folderId.equals('inbox'))
              ..orderBy([(table) => OrderingTerm.desc(table.receivedAt)])
              ..limit(pageSize, offset: page * pageSize))
            .get();

    if (cached.isEmpty) {
      await _cacheSeedMessages();
      return getInbox(page: page, pageSize: pageSize);
    }

    return cached
        .map(
          (row) => MailMessageSummary(
            id: row.id,
            folderId: row.folderId,
            subject: row.subject,
            sender: row.sender,
            preview: row.preview,
            receivedAt: row.receivedAt,
            isRead: row.isRead,
            hasAttachments: row.hasAttachments,
            sequence: row.sequence,
          ),
        )
        .toList();
  }

  @override
  Future<MailMessageDetail> getMessageDetail(String id) async {
    final cached = await (_appDatabase.select(
      _appDatabase.messageDetails,
    )..where((table) => table.id.equals(id))).getSingleOrNull();

    if (cached != null) {
      return MailMessageDetail(
        id: cached.id,
        subject: cached.subject,
        sender: cached.sender,
        recipients: cached.recipients.split(','),
        bodyPlain: cached.bodyPlain,
        bodyHtml: cached.bodyHtml,
        receivedAt: cached.receivedAt,
      );
    }

    final summary = _seedMessages.firstWhere((message) => message.id == id);
    final detail = MailMessageDetail(
      id: summary.id,
      subject: summary.subject,
      sender: summary.sender,
      recipients: const ['product@finestar.dev'],
      bodyPlain:
          'Hello,\n\nThis initial project scaffold already separates presentation, domain and data layers.\n\nRegards,\nFinestar Mail',
      bodyHtml: null,
      receivedAt: summary.receivedAt,
    );

    await _appDatabase
        .into(_appDatabase.messageDetails)
        .insertOnConflictUpdate(
          db.MessageDetailsCompanion.insert(
            id: detail.id,
            subject: detail.subject,
            sender: detail.sender,
            recipients: detail.recipients.join(','),
            bodyPlain: detail.bodyPlain,
            bodyHtml: Value(detail.bodyHtml),
            receivedAt: detail.receivedAt,
          ),
        );

    return detail;
  }

  Future<void> _cacheSeedMessages() async {
    await _appDatabase.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _appDatabase.messageSummaries,
        _seedMessages
            .map(
              (message) => db.MessageSummariesCompanion.insert(
                id: message.id,
                folderId: message.folderId,
                subject: message.subject,
                sender: message.sender,
                preview: message.preview,
                receivedAt: message.receivedAt,
                isRead: message.isRead,
                hasAttachments: message.hasAttachments,
                sequence: message.sequence,
              ),
            )
            .toList(),
      );
    });
  }
}
