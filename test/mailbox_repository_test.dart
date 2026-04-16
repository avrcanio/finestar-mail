import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finestar_mail/data/local/app_database.dart' as db;
import 'package:finestar_mail/features/mailbox/data/mailbox_repository_impl.dart';
import 'package:finestar_mail/features/mailbox/domain/entities/mail_folder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inbox cache is isolated by account id', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final repository = MailboxRepositoryImpl(appDatabase: database);

    final firstInbox = await repository.getInbox(
      accountId: 'app-test-1@finestar.hr',
      forceRefresh: true,
    );
    final secondInbox = await repository.getInbox(
      accountId: 'app-test-2@finestar.hr',
      forceRefresh: true,
    );

    expect(firstInbox, isNotEmpty);
    expect(secondInbox, isNotEmpty);
    expect(firstInbox.first.id, startsWith('app-test-1@finestar.hr:'));
    expect(secondInbox.first.id, startsWith('app-test-2@finestar.hr:'));
    expect(firstInbox.first.id, isNot(secondInbox.first.id));
  });

  test('folders fallback is isolated by account id', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final repository = MailboxRepositoryImpl(appDatabase: database);

    final firstFolders = await repository.getFolders('app-test-1@finestar.hr');
    final secondFolders = await repository.getFolders('app-test-2@finestar.hr');

    expect(firstFolders.map((folder) => folder.name), contains('INBOX'));
    expect(firstFolders.map((folder) => folder.name), contains('Sent'));
    expect(firstFolders.map((folder) => folder.name), contains('Drafts'));
    expect(firstFolders.map((folder) => folder.name), contains('Trash'));
    expect(firstFolders.map((folder) => folder.name), contains('Junk'));
    expect(firstFolders.first.id, startsWith('app-test-1@finestar.hr:'));
    expect(secondFolders.first.id, startsWith('app-test-2@finestar.hr:'));
    expect(firstFolders.first.id, isNot(secondFolders.first.id));
  });

  test('message cache is isolated by account and folder id', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    const inbox = MailFolder(
      id: 'app-test-2@finestar.hr:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    const sent = MailFolder(
      id: 'app-test-2@finestar.hr:sent',
      name: 'Sent',
      path: 'Sent',
      isInbox: false,
    );

    await database
        .into(database.messageSummaries)
        .insert(
          db.MessageSummariesCompanion.insert(
            id: 'app-test-2@finestar.hr:inbox:imap:1',
            accountId: const Value('app-test-2@finestar.hr'),
            folderId: inbox.id,
            subject: 'Inbox only',
            sender: 'inbox@finestar.hr',
            preview: 'Inbox preview',
            receivedAt: DateTime(2026, 4, 16),
            isRead: false,
            hasAttachments: false,
            sequence: 1,
          ),
        );
    await database
        .into(database.messageSummaries)
        .insert(
          db.MessageSummariesCompanion.insert(
            id: 'app-test-2@finestar.hr:sent:imap:1',
            accountId: const Value('app-test-2@finestar.hr'),
            folderId: sent.id,
            subject: 'Sent only',
            sender: 'sent@finestar.hr',
            preview: 'Sent preview',
            receivedAt: DateTime(2026, 4, 16),
            isRead: true,
            hasAttachments: false,
            sequence: 1,
          ),
        );

    final repository = MailboxRepositoryImpl(appDatabase: database);

    final inboxMessages = await repository.getMessages(
      accountId: 'app-test-2@finestar.hr',
      folder: inbox,
    );
    final sentMessages = await repository.getMessages(
      accountId: 'app-test-2@finestar.hr',
      folder: sent,
    );

    expect(inboxMessages, hasLength(1));
    expect(sentMessages, hasLength(1));
    expect(inboxMessages.single.subject, 'Inbox only');
    expect(sentMessages.single.subject, 'Sent only');
  });

  test('non-inbox folders do not get development seed messages', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final repository = MailboxRepositoryImpl(appDatabase: database);
    const sent = MailFolder(
      id: 'app-test-2@finestar.hr:sent',
      name: 'Sent',
      path: 'Sent',
      isInbox: false,
    );

    final messages = await repository.getMessages(
      accountId: 'app-test-2@finestar.hr',
      folder: sent,
      forceRefresh: true,
    );

    expect(messages, isEmpty);
  });
}
