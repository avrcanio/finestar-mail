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

  test('thread lookup includes cached messages from inbox and sent', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await _insertFolder(database, 'account:inbox', 'INBOX');
    await _insertFolder(database, 'account:sent', 'Sent');
    await _insertDetail(
      database,
      id: 'inbox-1',
      accountId: 'account',
      folderId: 'account:inbox',
      subject: 'Project update',
      sender: 'client@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 8),
    );
    await _insertDetail(
      database,
      id: 'sent-1',
      accountId: 'account',
      folderId: 'account:sent',
      subject: 'Re: Project update',
      sender: 'me@finestar.hr',
      recipients: 'client@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 9),
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final thread = await repository.getMessageThread(
      accountId: 'account',
      messageId: 'inbox-1',
    );

    expect(thread.messages.map((message) => message.id), ['inbox-1', 'sent-1']);
    expect(thread.messages.map((message) => message.folderName), [
      'INBOX',
      'Sent',
    ]);
  });

  test('thread lookup prefers RFC linkage over subject fallback', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await _insertFolder(database, 'account:inbox', 'INBOX');
    await _insertDetail(
      database,
      id: 'root',
      accountId: 'account',
      folderId: 'account:inbox',
      subject: 'Shared subject',
      sender: 'one@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 8),
      messageIdHeader: '<root@finestar.hr>',
    );
    await _insertDetail(
      database,
      id: 'reply',
      accountId: 'account',
      folderId: 'account:inbox',
      subject: 'Re: Shared subject',
      sender: 'me@finestar.hr',
      recipients: 'one@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 9),
      messageIdHeader: '<reply@finestar.hr>',
      inReplyToHeader: '<root@finestar.hr>',
      referencesHeader: '<root@finestar.hr>',
    );
    await _insertDetail(
      database,
      id: 'same-subject-unlinked',
      accountId: 'account',
      folderId: 'account:inbox',
      subject: 'Shared subject',
      sender: 'two@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 10),
      messageIdHeader: '<other@finestar.hr>',
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final thread = await repository.getMessageThread(
      accountId: 'account',
      messageId: 'root',
    );

    expect(thread.messages.map((message) => message.id), ['root', 'reply']);
  });

  test('thread lookup is isolated by account id', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await _insertFolder(database, 'first:inbox', 'INBOX', accountId: 'first');
    await _insertFolder(database, 'second:inbox', 'INBOX', accountId: 'second');
    await _insertDetail(
      database,
      id: 'first-message',
      accountId: 'first',
      folderId: 'first:inbox',
      subject: 'Same subject',
      sender: 'one@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 8),
    );
    await _insertDetail(
      database,
      id: 'second-message',
      accountId: 'second',
      folderId: 'second:inbox',
      subject: 'Same subject',
      sender: 'two@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 9),
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final thread = await repository.getMessageThread(
      accountId: 'first',
      messageId: 'first-message',
    );

    expect(thread.messages.map((message) => message.id), ['first-message']);
  });

  test('notification lookup maps RFC Message-ID to cached local id', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await _insertDetail(
      database,
      id: 'local-inbox-id',
      accountId: 'account',
      folderId: 'account:inbox',
      subject: 'Incoming push',
      sender: 'sender@finestar.hr',
      recipients: 'me@finestar.hr',
      receivedAt: DateTime(2026, 4, 16, 11),
      messageIdHeader: '<server-message@finestar.hr>',
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final localId = await repository.findCachedMessageId(
      accountId: 'account',
      rfcMessageId: '<server-message@finestar.hr>',
      subject: 'Incoming push',
      sender: 'Sender <sender@finestar.hr>',
    );

    expect(localId, 'local-inbox-id');
  });

  test(
    'notification lookup maps backend folder and uid to cached id',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await _insertSummary(
        database,
        id: 'account:inbox:api:42',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Backend push',
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      final localId = await repository.findCachedMessageId(
        accountId: 'account',
        folder: 'INBOX',
        uid: '42',
      );

      expect(localId, 'account:inbox:api:42');
    },
  );

  test(
    'thread loading can open a cached backend summary without detail',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await _insertSummary(
        database,
        id: 'account:inbox:api:42',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Backend push',
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      final thread = await repository.getMessageThread(
        accountId: 'account',
        messageId: 'account:inbox:api:42',
      );

      expect(thread.selectedMessageId, 'account:inbox:api:42');
      expect(thread.messages.single.subject, 'Backend push');
    },
  );

  test(
    'notification lookup falls back to newest subject and sender match',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await _insertDetail(
        database,
        id: 'older',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Re: Push subject',
        sender: 'sender@finestar.hr',
        recipients: 'me@finestar.hr',
        receivedAt: DateTime(2026, 4, 16, 8),
      );
      await _insertDetail(
        database,
        id: 'newer',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Push subject',
        sender: 'sender@finestar.hr',
        recipients: 'me@finestar.hr',
        receivedAt: DateTime(2026, 4, 16, 11),
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      final localId = await repository.findCachedMessageId(
        accountId: 'account',
        subject: 'Push subject',
        sender: 'Sender <sender@finestar.hr>',
      );

      expect(localId, 'newer');
    },
  );

  test(
    'setMessageRead marks read locally and stores pending server sync',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await _insertSummary(
        database,
        id: 'account:inbox:imap:1',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Unread',
        isRead: false,
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      await repository.setMessageRead(
        accountId: 'account',
        messageId: 'account:inbox:imap:1',
        isRead: true,
      );

      final row = await (database.select(
        database.messageSummaries,
      )..where((table) => table.id.equals('account:inbox:imap:1'))).getSingle();
      expect(row.isRead, isTrue);
      expect(row.pendingReadState, isTrue);
    },
  );

  test(
    'setMessageRead marks unread locally and stores pending server sync',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      await _insertSummary(
        database,
        id: 'account:inbox:imap:1',
        accountId: 'account',
        folderId: 'account:inbox',
        subject: 'Read',
        isRead: true,
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      await repository.setMessageRead(
        accountId: 'account',
        messageId: 'account:inbox:imap:1',
        isRead: false,
      );

      final row = await (database.select(
        database.messageSummaries,
      )..where((table) => table.id.equals('account:inbox:imap:1'))).getSingle();
      expect(row.isRead, isFalse);
      expect(row.pendingReadState, isFalse);
    },
  );

  test('pending unread state overrides cached server read state', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    const inbox = MailFolder(
      id: 'account:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    await _insertSummary(
      database,
      id: 'account:inbox:imap:1',
      accountId: 'account',
      folderId: inbox.id,
      subject: 'Pending unread',
      isRead: true,
      pendingReadState: false,
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final messages = await repository.getMessages(
      accountId: 'account',
      folder: inbox,
    );

    expect(messages.single.isRead, isFalse);
  });

  test(
    'important and pinned states persist across cached message reads',
    () async {
      final database = db.AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      const inbox = MailFolder(
        id: 'account:inbox',
        name: 'INBOX',
        path: 'INBOX',
        isInbox: true,
      );
      await _insertSummary(
        database,
        id: 'account:inbox:imap:1',
        accountId: 'account',
        folderId: inbox.id,
        subject: 'Status',
        isImportant: true,
        isPinned: true,
      );

      final repository = MailboxRepositoryImpl(appDatabase: database);
      final messages = await repository.getMessages(
        accountId: 'account',
        folder: inbox,
      );

      expect(messages.single.isImportant, isTrue);
      expect(messages.single.isPinned, isTrue);
    },
  );

  test('pinned messages sort above newer unpinned messages', () async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    const inbox = MailFolder(
      id: 'account:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    );
    await _insertSummary(
      database,
      id: 'account:inbox:imap:1',
      accountId: 'account',
      folderId: inbox.id,
      subject: 'Older pinned',
      receivedAt: DateTime(2026, 4, 16, 8),
      isPinned: true,
    );
    await _insertSummary(
      database,
      id: 'account:inbox:imap:2',
      accountId: 'account',
      folderId: inbox.id,
      subject: 'Newer unpinned',
      receivedAt: DateTime(2026, 4, 16, 10),
    );

    final repository = MailboxRepositoryImpl(appDatabase: database);
    final messages = await repository.getMessages(
      accountId: 'account',
      folder: inbox,
    );

    expect(messages.map((message) => message.subject), [
      'Older pinned',
      'Newer unpinned',
    ]);
  });
}

Future<void> _insertFolder(
  db.AppDatabase database,
  String id,
  String name, {
  String accountId = 'account',
}) {
  return database
      .into(database.mailFolders)
      .insert(
        db.MailFoldersCompanion.insert(
          id: id,
          accountId: accountId,
          name: name,
          path: name,
          isInbox: name == 'INBOX',
        ),
      );
}

Future<void> _insertDetail(
  db.AppDatabase database, {
  required String id,
  required String accountId,
  required String folderId,
  required String subject,
  required String sender,
  required String recipients,
  required DateTime receivedAt,
  String bodyPlain = 'Body',
  String? messageIdHeader,
  String? inReplyToHeader,
  String? referencesHeader,
}) {
  return database
      .into(database.messageDetails)
      .insert(
        db.MessageDetailsCompanion.insert(
          id: id,
          accountId: Value(accountId),
          folderId: Value(folderId),
          subject: subject,
          sender: sender,
          recipients: recipients,
          bodyPlain: bodyPlain,
          bodyHtml: const Value(null),
          receivedAt: receivedAt,
          messageIdHeader: Value(messageIdHeader),
          inReplyToHeader: Value(inReplyToHeader),
          referencesHeader: Value(referencesHeader),
        ),
      );
}

Future<void> _insertSummary(
  db.AppDatabase database, {
  required String id,
  required String accountId,
  required String folderId,
  required String subject,
  DateTime? receivedAt,
  bool isRead = true,
  bool? pendingReadState,
  bool isImportant = false,
  bool isPinned = false,
}) {
  return database
      .into(database.messageSummaries)
      .insert(
        db.MessageSummariesCompanion.insert(
          id: id,
          accountId: Value(accountId),
          folderId: folderId,
          subject: subject,
          sender: 'sender@finestar.hr',
          preview: 'Preview',
          receivedAt: receivedAt ?? DateTime(2026, 4, 16),
          isRead: isRead,
          pendingReadState: Value(pendingReadState),
          hasAttachments: false,
          sequence: 1,
          isImportant: Value(isImportant),
          isPinned: Value(isPinned),
        ),
      );
}
