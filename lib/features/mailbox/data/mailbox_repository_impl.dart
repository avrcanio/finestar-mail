import 'package:drift/drift.dart';
import 'package:enough_mail/imap.dart';

import '../../../data/local/app_database.dart' as db;
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/mail_folder.dart' as domain;
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_summary.dart';
import '../domain/entities/mail_thread.dart';
import '../domain/repositories/mailbox_repository.dart';

class MailboxRepositoryImpl implements MailboxRepository {
  MailboxRepositoryImpl({
    required db.AppDatabase appDatabase,
    SecureStorageService? secureStorageService,
  }) : _appDatabase = appDatabase,
       _secureStorageService = secureStorageService;

  final db.AppDatabase _appDatabase;
  final SecureStorageService? _secureStorageService;

  static List<domain.MailFolder> _fallbackFolders(String accountId) => [
    domain.MailFolder(
      id: '$accountId:inbox',
      name: 'INBOX',
      path: 'INBOX',
      isInbox: true,
    ),
    domain.MailFolder(
      id: '$accountId:sent',
      name: 'Sent',
      path: 'Sent',
      isInbox: false,
    ),
    domain.MailFolder(
      id: '$accountId:drafts',
      name: 'Drafts',
      path: 'Drafts',
      isInbox: false,
    ),
    domain.MailFolder(
      id: '$accountId:trash',
      name: 'Trash',
      path: 'Trash',
      isInbox: false,
    ),
    domain.MailFolder(
      id: '$accountId:junk',
      name: 'Junk',
      path: 'Junk',
      isInbox: false,
    ),
  ];

  static List<MailMessageSummary> _seedMessages(String accountId) =>
      List.generate(
        12,
        (index) => MailMessageSummary(
          id: '$accountId:msg_$index',
          folderId: '$accountId:inbox',
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
  Future<List<domain.MailFolder>> getFolders(String accountId) async {
    final remoteFolders = await _fetchRemoteFolders(accountId);
    if (remoteFolders != null && remoteFolders.isNotEmpty) {
      await _replaceCachedFolders(accountId, remoteFolders);
      return remoteFolders;
    }

    final cachedFolders = await _cachedFolders(accountId);
    if (cachedFolders.isNotEmpty) {
      return cachedFolders;
    }

    final fallbackFolders = _fallbackFolders(accountId);
    await _replaceCachedFolders(accountId, fallbackFolders);
    return fallbackFolders;
  }

  Future<List<domain.MailFolder>?> _fetchRemoteFolders(String accountId) async {
    final secureStorageService = _secureStorageService;
    if (secureStorageService == null) {
      return null;
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(accountId))).getSingleOrNull();
    final password = await secureStorageService.readPassword(accountId);
    if (account == null || password == null || password.isEmpty) {
      return null;
    }

    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: account.imapSecurity == 'sslTls',
        timeout: const Duration(seconds: 12),
      );
      if (account.imapSecurity == 'startTls') {
        await client.startTls();
      }
      await client.login(account.email, password);

      final mailboxes = await client.listMailboxes(recursive: true);
      return mailboxes
          .where((mailbox) => !mailbox.isNotSelectable)
          .map(
            (mailbox) => domain.MailFolder(
              id: _folderId(accountId, mailbox.path),
              name: mailbox.name,
              path: mailbox.path,
              isInbox: _isInboxMailbox(mailbox),
            ),
          )
          .toList();
    } catch (_) {
      return null;
    } finally {
      await client.disconnect();
    }
  }

  Future<void> _replaceCachedFolders(
    String accountId,
    List<domain.MailFolder> folders,
  ) async {
    await _appDatabase.batch((batch) {
      batch.deleteWhere(
        _appDatabase.mailFolders,
        (table) => table.accountId.equals(accountId),
      );
      batch.insertAllOnConflictUpdate(
        _appDatabase.mailFolders,
        folders
            .map(
              (folder) => db.MailFoldersCompanion.insert(
                id: folder.id,
                accountId: accountId,
                name: folder.name,
                path: folder.path,
                isInbox: folder.isInbox,
              ),
            )
            .toList(),
      );
    });
  }

  Future<List<domain.MailFolder>> _cachedFolders(String accountId) async {
    final rows = await (_appDatabase.select(
      _appDatabase.mailFolders,
    )..where((table) => table.accountId.equals(accountId))).get();
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

  String _folderId(String accountId, String path) {
    final normalizedPath = path.trim().toLowerCase();
    return '$accountId:$normalizedPath';
  }

  bool _isInboxMailbox(Mailbox mailbox) {
    final normalizedPath = mailbox.path.trim().toLowerCase();
    final normalizedName = mailbox.name.trim().toLowerCase();
    return mailbox.isInbox ||
        normalizedPath == 'inbox' ||
        normalizedName == 'inbox';
  }

  @override
  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    final folders = await getFolders(accountId);
    final inbox = folders.firstWhere(
      (folder) => folder.isInbox || folder.path.toLowerCase() == 'inbox',
      orElse: () => _fallbackFolders(accountId).first,
    );
    return getMessages(
      accountId: accountId,
      folder: inbox,
      page: page,
      pageSize: pageSize,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<List<MailMessageSummary>> getMessages({
    required String accountId,
    required domain.MailFolder folder,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      final remoteMessages = await _fetchRemoteMessages(
        accountId: accountId,
        folder: folder,
        pageSize: pageSize,
      );
      if (remoteMessages != null) {
        if (remoteMessages.isNotEmpty) {
          return remoteMessages;
        }
      }
    }

    final cached =
        await (_appDatabase.select(_appDatabase.messageSummaries)
              ..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.folderId.equals(folder.id),
              )
              ..orderBy([(table) => OrderingTerm.desc(table.receivedAt)])
              ..limit(pageSize, offset: page * pageSize))
            .get();

    if (cached.isEmpty && folder.isInbox) {
      await _cacheSeedMessages(accountId);
      return getMessages(
        accountId: accountId,
        folder: folder,
        page: page,
        pageSize: pageSize,
      );
    }

    return cached.map(_summaryFromRow).toList();
  }

  @override
  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  }) async {
    final cached =
        await (_appDatabase.select(_appDatabase.messageDetails)..where(
              (table) =>
                  table.id.equals(id) & table.accountId.equals(accountId),
            ))
            .getSingleOrNull();

    if (cached != null) {
      return MailMessageDetail(
        id: cached.id,
        subject: cached.subject,
        sender: cached.sender,
        recipients: _splitRecipients(cached.recipients),
        bodyPlain: cached.bodyPlain,
        bodyHtml: cached.bodyHtml,
        receivedAt: cached.receivedAt,
      );
    }

    final cachedFallback = await _cacheFallbackDetail(accountId, id);
    return MailMessageDetail(
      id: cachedFallback.id,
      subject: cachedFallback.subject,
      sender: cachedFallback.sender,
      recipients: _splitRecipients(cachedFallback.recipients),
      bodyPlain: cachedFallback.bodyPlain,
      bodyHtml: cachedFallback.bodyHtml,
      receivedAt: cachedFallback.receivedAt,
    );
  }

  Future<db.MessageDetail> _cacheFallbackDetail(
    String accountId,
    String id,
  ) async {
    final summary = _seedMessages(
      accountId,
    ).firstWhere((message) => message.id == id);
    final detail = MailMessageDetail(
      id: summary.id,
      subject: summary.subject,
      sender: summary.sender,
      recipients: const ['product@finestar.dev'],
      bodyPlain:
          'Hello,\n\nThis initial project scaffold already separates presentation, domain and data layers.\n\nRegards,\nFS Mail',
      bodyHtml: null,
      receivedAt: summary.receivedAt,
    );

    await _appDatabase
        .into(_appDatabase.messageDetails)
        .insertOnConflictUpdate(
          db.MessageDetailsCompanion.insert(
            id: detail.id,
            accountId: Value(accountId),
            folderId: Value(summary.folderId),
            subject: detail.subject,
            sender: detail.sender,
            recipients: detail.recipients.join(','),
            bodyPlain: detail.bodyPlain,
            bodyHtml: Value(detail.bodyHtml),
            receivedAt: detail.receivedAt,
          ),
        );

    return (await (_appDatabase.select(_appDatabase.messageDetails)..where(
          (table) => table.id.equals(id) & table.accountId.equals(accountId),
        ))
        .getSingle());
  }

  @override
  Future<MailThread> getMessageThread({
    required String accountId,
    required String messageId,
  }) async {
    var selected =
        await (_appDatabase.select(_appDatabase.messageDetails)..where(
              (table) =>
                  table.id.equals(messageId) &
                  table.accountId.equals(accountId),
            ))
            .getSingleOrNull();

    selected ??= await _cacheFallbackDetail(accountId, messageId);

    await _syncSentMessagesForThread(accountId, selected);

    final allDetails = await (_appDatabase.select(
      _appDatabase.messageDetails,
    )..where((table) => table.accountId.equals(accountId))).get();
    final folders = await _cachedFolders(accountId);
    final folderNames = {
      for (final folder in folders) folder.id: _folderLabel(folder),
    };

    final selectedMessage = selected;
    final selectedTokens = _threadHeaderTokens(selectedMessage);
    var threadRows = selectedTokens.isEmpty
        ? <db.MessageDetail>[]
        : allDetails
              .where(
                (row) =>
                    row.id == selectedMessage.id ||
                    _threadHeaderTokens(
                      row,
                    ).any((token) => selectedTokens.contains(token)),
              )
              .toList();

    if (threadRows.length <= 1) {
      final normalizedSubject = _normalizeThreadSubject(
        selectedMessage.subject,
      );
      threadRows = allDetails
          .where(
            (row) => _normalizeThreadSubject(row.subject) == normalizedSubject,
          )
          .toList();
    }

    threadRows.sort(
      (left, right) => left.receivedAt.compareTo(right.receivedAt),
    );
    return MailThread(
      subject: selectedMessage.subject,
      selectedMessageId: selectedMessage.id,
      messages: threadRows
          .map((row) => _threadMessageFromRow(row, folderNames))
          .toList(),
    );
  }

  Future<void> _syncSentMessagesForThread(
    String accountId,
    db.MessageDetail selected,
  ) async {
    final secureStorageService = _secureStorageService;
    if (secureStorageService == null) {
      return;
    }

    final threadSubject = _normalizeThreadSubject(selected.subject);
    if (threadSubject.isEmpty || threadSubject == '(no subject)') {
      return;
    }

    final folders = await getFolders(accountId);
    final sentFolders = folders.where(_isSentFolder).toList();
    for (final folder in sentFolders) {
      await _searchRemoteMessages(
        accountId: accountId,
        folder: folder,
        query: threadSubject,
        limit: 30,
      );
    }
  }

  @override
  Future<List<MailMessageSummary>> searchMessages({
    required String accountId,
    required domain.MailFolder folder,
    required String query,
    int limit = 30,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final remoteMessages = await _searchRemoteMessages(
      accountId: accountId,
      folder: folder,
      query: normalizedQuery,
      limit: limit,
    );
    if (remoteMessages != null) {
      return remoteMessages;
    }

    final likeQuery = '%${normalizedQuery.toLowerCase()}%';
    final cached =
        await (_appDatabase.select(_appDatabase.messageSummaries)
              ..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.folderId.equals(folder.id) &
                    (table.subject.lower().like(likeQuery) |
                        table.sender.lower().like(likeQuery) |
                        table.preview.lower().like(likeQuery)),
              )
              ..orderBy([(table) => OrderingTerm.desc(table.receivedAt)])
              ..limit(limit))
            .get();

    return cached.map(_summaryFromRow).toList();
  }

  Future<void> _cacheSeedMessages(String accountId) async {
    final inboxFolder = _fallbackFolders(accountId).first;
    await _appDatabase.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _appDatabase.messageSummaries,
        _seedMessages(accountId)
            .map(
              (message) => db.MessageSummariesCompanion.insert(
                id: message.id,
                accountId: Value(accountId),
                folderId: inboxFolder.id,
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

  Future<List<MailMessageSummary>?> _searchRemoteMessages({
    required String accountId,
    required domain.MailFolder folder,
    required String query,
    required int limit,
  }) async {
    final secureStorageService = _secureStorageService;
    if (secureStorageService == null) {
      return null;
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(accountId))).getSingleOrNull();
    final password = await secureStorageService.readPassword(accountId);
    if (account == null || password == null || password.isEmpty) {
      return null;
    }

    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: account.imapSecurity == 'sslTls',
        timeout: const Duration(seconds: 12),
      );
      if (account.imapSecurity == 'startTls') {
        await client.startTls();
      }
      await client.login(account.email, password);
      await client.selectMailboxByPath(folder.path);

      var searchResult = await client.searchMessagesWithQuery(
        SearchQueryBuilder.from(query, SearchQueryType.fromOrSubject),
        responseTimeout: const Duration(seconds: 12),
      );
      var sequence = searchResult.matchingSequence;
      if (sequence == null || sequence.isEmpty) {
        searchResult = await client.searchMessagesWithQuery(
          SearchQueryBuilder.from(query, SearchQueryType.body),
          responseTimeout: const Duration(seconds: 12),
        );
        sequence = searchResult.matchingSequence;
      }
      if (sequence == null || sequence.isEmpty) {
        return const [];
      }

      final ids = sequence.toList();
      final limitedIds = ids.length > limit
          ? ids.sublist(ids.length - limit)
          : ids;
      final fetchResult = await client.fetchMessages(
        MessageSequence.fromIds(limitedIds),
        '(FLAGS BODY.PEEK[])',
        responseTimeout: const Duration(seconds: 20),
      );

      return _cacheMessages(accountId, folder, fetchResult.messages.reversed);
    } catch (_) {
      return null;
    } finally {
      await client.disconnect();
    }
  }

  Future<List<MailMessageSummary>?> _fetchRemoteMessages({
    required String accountId,
    required domain.MailFolder folder,
    required int pageSize,
  }) async {
    final secureStorageService = _secureStorageService;
    if (secureStorageService == null) {
      return null;
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(accountId))).getSingleOrNull();
    final password = await secureStorageService.readPassword(accountId);
    if (account == null || password == null || password.isEmpty) {
      return null;
    }

    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: account.imapSecurity == 'sslTls',
        timeout: const Duration(seconds: 12),
      );
      if (account.imapSecurity == 'startTls') {
        await client.startTls();
      }
      await client.login(account.email, password);
      await client.selectMailboxByPath(folder.path);
      final result = await client.fetchRecentMessages(
        messageCount: pageSize,
        criteria: '(FLAGS BODY.PEEK[])',
        responseTimeout: const Duration(seconds: 20),
      );

      return _cacheMessages(accountId, folder, result.messages.reversed);
    } catch (_) {
      return null;
    } finally {
      await client.disconnect();
    }
  }

  Future<List<MailMessageSummary>> _cacheMessages(
    String accountId,
    domain.MailFolder folder,
    Iterable<MimeMessage> messages,
  ) async {
    final details = <db.MessageDetailsCompanion>[];
    final summaries = messages.map((message) {
      final messageId = _messageId(accountId, folder, message);
      final bodyPlain = message.decodeTextPlainPart() ?? '';
      final bodyHtml = message.decodeTextHtmlPart();
      final receivedAt = message.decodeDate() ?? DateTime.now();
      final sender = _sender(message);
      final recipients = message.recipients.map((address) => address.email);
      final subject = message.decodeSubject() ?? '(No subject)';

      details.add(
        db.MessageDetailsCompanion.insert(
          id: messageId,
          accountId: Value(accountId),
          folderId: Value(folder.id),
          subject: subject,
          sender: sender,
          recipients: recipients.join(','),
          bodyPlain: bodyPlain,
          bodyHtml: Value(bodyHtml),
          receivedAt: receivedAt,
          messageIdHeader: Value(message.getHeaderValue('Message-ID')),
          inReplyToHeader: Value(message.getHeaderValue('In-Reply-To')),
          referencesHeader: Value(message.getHeaderValue('References')),
        ),
      );

      return MailMessageSummary(
        id: messageId,
        folderId: folder.id,
        subject: subject,
        sender: sender,
        preview: _preview(bodyPlain),
        receivedAt: receivedAt,
        isRead: message.isSeen,
        hasAttachments: message.hasAttachments(),
        sequence: message.sequenceId ?? message.uid ?? 0,
      );
    }).toList();

    await _appDatabase.batch((batch) {
      batch.insertAllOnConflictUpdate(_appDatabase.messageDetails, details);
      batch.insertAllOnConflictUpdate(
        _appDatabase.messageSummaries,
        summaries
            .map(
              (message) => db.MessageSummariesCompanion.insert(
                id: message.id,
                accountId: Value(accountId),
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

    return summaries;
  }

  MailMessageSummary _summaryFromRow(db.MessageSummary row) {
    return MailMessageSummary(
      id: row.id,
      folderId: row.folderId,
      subject: row.subject,
      sender: row.sender,
      preview: row.preview,
      receivedAt: row.receivedAt,
      isRead: row.isRead,
      hasAttachments: row.hasAttachments,
      sequence: row.sequence,
    );
  }

  MailThreadMessage _threadMessageFromRow(
    db.MessageDetail row,
    Map<String, String> folderNames,
  ) {
    final fallbackFolder = row.folderId.isEmpty ? 'Mail' : row.folderId;
    return MailThreadMessage(
      id: row.id,
      folderId: row.folderId,
      folderName: folderNames[row.folderId] ?? fallbackFolder,
      subject: row.subject,
      sender: row.sender,
      recipients: _splitRecipients(row.recipients),
      bodyPlain: row.bodyPlain,
      bodyHtml: row.bodyHtml,
      receivedAt: row.receivedAt,
      messageIdHeader: row.messageIdHeader,
      inReplyToHeader: row.inReplyToHeader,
      referencesHeader: row.referencesHeader,
    );
  }

  Set<String> _threadHeaderTokens(db.MessageDetail row) {
    return {
      ..._messageIdTokens(row.messageIdHeader),
      ..._messageIdTokens(row.inReplyToHeader),
      ..._messageIdTokens(row.referencesHeader),
    };
  }

  Set<String> _messageIdTokens(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const {};
    }

    final matches = RegExp(r'<[^>]+>|[^\s]+').allMatches(raw);
    return matches
        .map((match) => match.group(0)?.trim())
        .whereType<String>()
        .map((value) => value.toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String _normalizeThreadSubject(String subject) {
    var normalized = subject.trim().toLowerCase();
    var previous = '';
    final prefixPattern = RegExp(r'^(re|fw|fwd):\s*', caseSensitive: false);
    while (normalized != previous) {
      previous = normalized;
      normalized = normalized.replaceFirst(prefixPattern, '').trim();
    }
    return normalized.isEmpty ? '(no subject)' : normalized;
  }

  List<String> _splitRecipients(String recipients) {
    return recipients
        .split(',')
        .map((recipient) => recipient.trim())
        .where((recipient) => recipient.isNotEmpty)
        .toList();
  }

  String _folderLabel(domain.MailFolder folder) {
    return folder.name.trim().isEmpty ? folder.path : folder.name;
  }

  bool _isSentFolder(domain.MailFolder folder) {
    final normalizedPath = folder.path.trim().toLowerCase();
    final normalizedName = folder.name.trim().toLowerCase();
    return normalizedPath == 'sent' ||
        normalizedName == 'sent' ||
        normalizedPath.contains('sent mail') ||
        normalizedName.contains('sent mail') ||
        normalizedPath.contains('/sent') ||
        normalizedName.contains('poslano') ||
        normalizedPath.contains('poslano');
  }

  String _messageId(
    String accountId,
    domain.MailFolder folder,
    MimeMessage message,
  ) {
    final remoteId = message.uid ?? message.sequenceId ?? message.guid;
    final normalizedPath = folder.path.trim().toLowerCase();
    return '$accountId:$normalizedPath:imap:${remoteId ?? message.hashCode}';
  }

  String _sender(MimeMessage message) {
    final from = message.from;
    if (from != null && from.isNotEmpty) {
      return from.first.email;
    }
    return message.fromEmail ?? 'unknown sender';
  }

  String _preview(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 140) {
      return collapsed;
    }
    return '${collapsed.substring(0, 140)}...';
  }
}
