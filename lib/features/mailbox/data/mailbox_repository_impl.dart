import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../../data/remote/backend_mail_api_client.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/mail_folder.dart' as domain;
import '../domain/entities/mail_message_detail.dart';
import '../domain/entities/mail_message_page.dart';
import '../domain/entities/mail_message_summary.dart';
import '../domain/entities/mail_thread.dart';
import '../domain/repositories/mailbox_repository.dart';

class MailboxRepositoryImpl implements MailboxRepository {
  MailboxRepositoryImpl({
    required db.AppDatabase appDatabase,
    SecureStorageService? secureStorageService,
    BackendMailApiClient? backendMailApiClient,
  }) : _appDatabase = appDatabase,
       _secureStorageService = secureStorageService,
       _backendMailApiClient = backendMailApiClient;

  final db.AppDatabase _appDatabase;
  final SecureStorageService? _secureStorageService;
  final BackendMailApiClient? _backendMailApiClient;

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
    final remoteFolders = await _fetchBackendFolders(accountId);
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

  Future<List<domain.MailFolder>?> _fetchBackendFolders(
    String accountId,
  ) async {
    final token = await _authToken(accountId);
    if (token == null) {
      return null;
    }

    final response = await _backendMailApiClient!.folders(token: token);
    return response.folders
        .where((folder) => folder.name.trim().isNotEmpty)
        .map(
          (folder) => domain.MailFolder(
            id: _folderId(accountId, folder.name),
            name: folder.name,
            path: folder.name,
            isInbox: _isInboxPath(folder.name),
          ),
        )
        .toList();
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

  @override
  Future<List<MailMessageSummary>> getInbox({
    required String accountId,
    int page = 0,
    int pageSize = 20,
    bool forceRefresh = false,
  }) async {
    final folders = await getFolders(accountId);
    final inbox = folders.firstWhere(
      (folder) => folder.isInbox || _isInboxPath(folder.path),
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
    if (page == 0) {
      final pageResult = await getMessagePage(
        accountId: accountId,
        folder: folder,
        pageSize: pageSize,
        forceRefresh: forceRefresh,
      );
      return pageResult.messages;
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

    if (cached.isEmpty && folder.isInbox && _backendMailApiClient == null) {
      await _cacheSeedMessages(accountId);
      return getMessages(
        accountId: accountId,
        folder: folder,
        page: page,
        pageSize: pageSize,
      );
    }

    return _sortSummaries(cached.map(_summaryFromRow).toList());
  }

  @override
  Future<MailMessagePage> getMessagePage({
    required String accountId,
    required domain.MailFolder folder,
    int pageSize = 50,
    String? beforeUid,
    bool forceRefresh = false,
  }) async {
    final remotePage = await _fetchBackendMessagePage(
      accountId: accountId,
      folder: folder,
      pageSize: pageSize,
      beforeUid: beforeUid,
    );
    if (remotePage != null) {
      return remotePage;
    }

    final cachedPage = await _cachedMessagePage(
      accountId: accountId,
      folder: folder,
      pageSize: pageSize,
      beforeUid: beforeUid,
    );
    if (cachedPage.messages.isEmpty &&
        folder.isInbox &&
        _backendMailApiClient == null) {
      await _cacheSeedMessages(accountId);
      return _cachedMessagePage(
        accountId: accountId,
        folder: folder,
        pageSize: pageSize,
        beforeUid: beforeUid,
      );
    }
    return cachedPage;
  }

  Future<MailMessagePage?> _fetchBackendMessagePage({
    required String accountId,
    required domain.MailFolder folder,
    required int pageSize,
    String? beforeUid,
  }) async {
    final token = await _authToken(accountId);
    if (token == null) {
      return null;
    }

    final response = await _backendMailApiClient!.messages(
      token: token,
      folder: folder.path,
      limit: pageSize,
      beforeUid: beforeUid,
    );
    final summaries = await _cacheBackendSummaries(
      accountId,
      folder,
      response.messages,
    );
    return MailMessagePage(
      messages: summaries,
      hasMore: response.hasMore,
      nextBeforeUid: response.nextBeforeUid,
    );
  }

  Future<MailMessagePage> _cachedMessagePage({
    required String accountId,
    required domain.MailFolder folder,
    required int pageSize,
    String? beforeUid,
  }) async {
    final rows =
        await (_appDatabase.select(_appDatabase.messageSummaries)
              ..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.folderId.equals(folder.id),
              )
              ..orderBy([(table) => OrderingTerm.desc(table.receivedAt)]))
            .get();
    final beforeUidNumber = int.tryParse(beforeUid?.trim() ?? '');
    final eligible = rows.where((row) {
      if (beforeUidNumber == null) {
        return true;
      }
      final uidNumber = int.tryParse(_uidFromMessageId(row.id) ?? '');
      return uidNumber != null && uidNumber < beforeUidNumber;
    }).toList();
    final selected = eligible.take(pageSize).map(_summaryFromRow).toList();
    final rawNextBeforeUid = selected.isEmpty
        ? null
        : _uidFromMessageId(selected.last.id);
    final hasMore =
        eligible.length > selected.length && rawNextBeforeUid != null;

    return MailMessagePage(
      messages: _sortSummaries(selected),
      hasMore: hasMore,
      nextBeforeUid: hasMore ? rawNextBeforeUid : null,
    );
  }

  Future<List<MailMessageSummary>> _cacheBackendSummaries(
    String accountId,
    domain.MailFolder folder,
    List<BackendMessageSummaryDto> messages,
  ) async {
    final summaries = messages.map((message) {
      final folderPath = message.folder.isEmpty ? folder.path : message.folder;
      final folderId = _folderId(accountId, folderPath);
      return MailMessageSummary(
        id: _messageId(accountId, folderPath, message.uid),
        folderId: folderId,
        subject: _subject(message.subject),
        sender: _sender(message.sender),
        preview: _preview(message.subject),
        receivedAt: message.date ?? DateTime.now(),
        isRead: _hasFlag(message.flags, 'seen'),
        isImportant: _hasFlag(message.flags, 'flagged'),
        hasAttachments: false,
        sequence: int.tryParse(message.uid) ?? 0,
      );
    }).toList();

    final existingRows = summaries.isEmpty
        ? <db.MessageSummary>[]
        : await (_appDatabase.select(
            _appDatabase.messageSummaries,
          )..where((table) => table.id.isIn(summaries.map((m) => m.id)))).get();
    final existingById = {for (final row in existingRows) row.id: row};
    final mergedSummaries = summaries.map((message) {
      final existing = existingById[message.id];
      if (existing == null) {
        return message;
      }
      return MailMessageSummary(
        id: message.id,
        folderId: message.folderId,
        subject: message.subject,
        sender: message.sender,
        preview: message.preview,
        receivedAt: message.receivedAt,
        isRead: existing.pendingReadState ?? message.isRead,
        hasAttachments: message.hasAttachments,
        sequence: message.sequence,
        isImportant: message.isImportant || existing.isImportant,
        isPinned: existing.isPinned,
      );
    }).toList();

    await _appDatabase.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _appDatabase.messageSummaries,
        summaries.map((message) {
          final existing = existingById[message.id];
          return db.MessageSummariesCompanion.insert(
            id: message.id,
            accountId: Value(accountId),
            folderId: message.folderId,
            subject: message.subject,
            sender: message.sender,
            preview: message.preview,
            receivedAt: message.receivedAt,
            isRead: message.isRead,
            pendingReadState: Value(
              _nextPendingReadState(message, existingById),
            ),
            hasAttachments: message.hasAttachments,
            sequence: message.sequence,
            isImportant: Value(
              message.isImportant || (existing?.isImportant ?? false),
            ),
            isPinned: Value(existing?.isPinned ?? false),
          );
        }).toList(),
      );
    });

    return _sortSummaries(mergedSummaries);
  }

  @override
  Future<MailMessageDetail> getMessageDetail({
    required String accountId,
    required String id,
  }) async {
    final remoteDetail = await _fetchBackendDetail(
      accountId: accountId,
      id: id,
    );
    if (remoteDetail != null) {
      return remoteDetail;
    }

    final cached =
        await (_appDatabase.select(_appDatabase.messageDetails)..where(
              (table) =>
                  table.id.equals(id) & table.accountId.equals(accountId),
            ))
            .getSingleOrNull();

    if (cached != null) {
      return _detailFromRow(cached);
    }

    final cachedFallback = await _cacheFallbackDetail(accountId, id);
    return _detailFromRow(cachedFallback);
  }

  Future<MailMessageDetail?> _fetchBackendDetail({
    required String accountId,
    required String id,
  }) async {
    final token = await _authToken(accountId);
    final uid = _uidFromMessageId(id);
    if (token == null || uid == null) {
      return null;
    }

    final folderPath = await _folderPathForMessage(accountId, id);
    final response = await _backendMailApiClient!.messageDetail(
      token: token,
      folder: folderPath,
      uid: uid,
    );
    final message = response.message;
    final folder = message.folder.isEmpty ? folderPath : message.folder;
    final folderId = _folderId(accountId, folder);
    final messageId = _messageId(accountId, folder, message.uid);
    final receivedAt = message.date ?? DateTime.now();
    final detail = MailMessageDetail(
      id: messageId,
      subject: _subject(message.subject),
      sender: _sender(message.sender),
      recipients: [...message.to, ...message.cc],
      bodyPlain: message.textBody,
      bodyHtml: message.htmlBody.isEmpty ? null : message.htmlBody,
      receivedAt: receivedAt,
    );

    await _appDatabase.batch((batch) {
      batch.insert(
        _appDatabase.mailFolders,
        db.MailFoldersCompanion.insert(
          id: folderId,
          accountId: accountId,
          name: folder,
          path: folder,
          isInbox: _isInboxPath(folder),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      batch.insert(
        _appDatabase.messageDetails,
        db.MessageDetailsCompanion.insert(
          id: messageId,
          accountId: Value(accountId),
          folderId: Value(folderId),
          subject: detail.subject,
          sender: detail.sender,
          recipients: detail.recipients.join(','),
          bodyPlain: detail.bodyPlain,
          bodyHtml: Value(detail.bodyHtml),
          receivedAt: detail.receivedAt,
          messageIdHeader: Value(message.messageId),
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        _appDatabase.messageSummaries,
        db.MessageSummariesCompanion.insert(
          id: messageId,
          accountId: Value(accountId),
          folderId: folderId,
          subject: detail.subject,
          sender: detail.sender,
          preview: _preview(detail.bodyPlain),
          receivedAt: receivedAt,
          isRead: _hasFlag(message.flags, 'seen'),
          hasAttachments: message.attachments.isNotEmpty,
          sequence: int.tryParse(message.uid) ?? 0,
          isImportant: Value(_hasFlag(message.flags, 'flagged')),
        ),
        mode: InsertMode.insertOrReplace,
      );
    });

    return detail;
  }

  Future<db.MessageDetail> _cacheFallbackDetail(
    String accountId,
    String id,
  ) async {
    final cachedSummary =
        await (_appDatabase.select(_appDatabase.messageSummaries)..where(
              (table) =>
                  table.id.equals(id) & table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    final summary = cachedSummary == null
        ? _seedSummaryForId(accountId, id)
        : MailMessageSummary(
            id: cachedSummary.id,
            folderId: cachedSummary.folderId,
            subject: cachedSummary.subject,
            sender: cachedSummary.sender,
            preview: cachedSummary.preview,
            receivedAt: cachedSummary.receivedAt,
            isRead: cachedSummary.pendingReadState ?? cachedSummary.isRead,
            hasAttachments: cachedSummary.hasAttachments,
            sequence: cachedSummary.sequence,
            isImportant: cachedSummary.isImportant,
            isPinned: cachedSummary.isPinned,
          );
    if (summary == null) {
      throw StateError('Message not found.');
    }
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

  MailMessageSummary? _seedSummaryForId(String accountId, String id) {
    for (final message in _seedMessages(accountId)) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
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

    if (selected == null) {
      await _fetchBackendDetail(accountId: accountId, id: messageId);
      selected =
          await (_appDatabase.select(_appDatabase.messageDetails)..where(
                (table) =>
                    table.id.equals(messageId) &
                    table.accountId.equals(accountId),
              ))
              .getSingleOrNull();
    }

    selected ??= await _cacheFallbackDetail(accountId, messageId);

    final allDetails = await (_appDatabase.select(
      _appDatabase.messageDetails,
    )..where((table) => table.accountId.equals(accountId))).get();
    final folders = await _cachedFolders(accountId);
    final folderNames = {
      for (final folder in folders) folder.id: _folderLabel(folder),
    };

    final selectedTokens = _threadHeaderTokens(selected);
    var threadRows = selectedTokens.isEmpty
        ? <db.MessageDetail>[]
        : allDetails
              .where(
                (row) =>
                    row.id == selected!.id ||
                    _threadHeaderTokens(
                      row,
                    ).any((token) => selectedTokens.contains(token)),
              )
              .toList();

    if (threadRows.length <= 1) {
      final normalizedSubject = _normalizeThreadSubject(selected.subject);
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
      subject: selected.subject,
      selectedMessageId: selected.id,
      messages: threadRows
          .map((row) => _threadMessageFromRow(row, folderNames))
          .toList(),
    );
  }

  @override
  Future<String?> findCachedMessageId({
    required String accountId,
    String? localMessageId,
    String? folder,
    String? uid,
    String? rfcMessageId,
    String? subject,
    String? sender,
  }) async {
    final trimmedLocalId = localMessageId?.trim();
    if (trimmedLocalId != null && trimmedLocalId.isNotEmpty) {
      final localMatch =
          await (_appDatabase.select(_appDatabase.messageDetails)..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.id.equals(trimmedLocalId),
              ))
              .getSingleOrNull();
      if (localMatch != null) {
        return localMatch.id;
      }
    }

    final trimmedFolder = folder?.trim();
    final trimmedUid = uid?.trim();
    if (trimmedFolder != null &&
        trimmedFolder.isNotEmpty &&
        trimmedUid != null &&
        trimmedUid.isNotEmpty) {
      final backendMessageId = _messageId(accountId, trimmedFolder, trimmedUid);
      final summaryMatch =
          await (_appDatabase.select(_appDatabase.messageSummaries)..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.id.equals(backendMessageId),
              ))
              .getSingleOrNull();
      if (summaryMatch != null) {
        return summaryMatch.id;
      }

      final detailMatch =
          await (_appDatabase.select(_appDatabase.messageDetails)..where(
                (table) =>
                    table.accountId.equals(accountId) &
                    table.id.equals(backendMessageId),
              ))
              .getSingleOrNull();
      if (detailMatch != null) {
        return detailMatch.id;
      }
    }

    final rows = await (_appDatabase.select(
      _appDatabase.messageDetails,
    )..where((table) => table.accountId.equals(accountId))).get();

    final rfcTokens = _messageIdTokens(rfcMessageId);
    if (rfcTokens.isNotEmpty) {
      for (final row in rows) {
        if (_messageIdTokens(
          row.messageIdHeader,
        ).any((token) => rfcTokens.contains(token))) {
          return row.id;
        }
      }
    }

    final normalizedSubject = subject == null
        ? null
        : _normalizeThreadSubject(subject);
    if (normalizedSubject == null ||
        normalizedSubject.isEmpty ||
        normalizedSubject == '(no subject)') {
      return null;
    }

    final normalizedSender = _normalizeAddressish(sender);
    final subjectMatches =
        rows
            .where(
              (row) =>
                  _normalizeThreadSubject(row.subject) == normalizedSubject,
            )
            .where((row) {
              if (normalizedSender == null) {
                return true;
              }
              final rowSender = _normalizeAddressish(row.sender);
              return rowSender != null &&
                  (rowSender.contains(normalizedSender) ||
                      normalizedSender.contains(rowSender));
            })
            .toList()
          ..sort((left, right) => right.receivedAt.compareTo(left.receivedAt));

    return subjectMatches.isEmpty ? null : subjectMatches.first.id;
  }

  @override
  Future<void> setMessageRead({
    required String accountId,
    required String messageId,
    required bool isRead,
  }) async {
    await _updateCachedSummary(
      accountId: accountId,
      messageId: messageId,
      companion: db.MessageSummariesCompanion(
        isRead: Value(isRead),
        pendingReadState: Value(isRead),
      ),
    );
  }

  @override
  Future<void> setMessageImportant({
    required String accountId,
    required String messageId,
    required bool isImportant,
  }) async {
    await _updateCachedSummary(
      accountId: accountId,
      messageId: messageId,
      companion: db.MessageSummariesCompanion(isImportant: Value(isImportant)),
    );
  }

  @override
  Future<void> setMessagePinned({
    required String accountId,
    required String messageId,
    required bool isPinned,
  }) async {
    await _updateCachedSummary(
      accountId: accountId,
      messageId: messageId,
      companion: db.MessageSummariesCompanion(isPinned: Value(isPinned)),
    );
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

    return _sortSummaries(cached.map(_summaryFromRow).toList());
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
                isImportant: Value(message.isImportant),
                isPinned: Value(message.isPinned),
              ),
            )
            .toList(),
      );
    });
  }

  MailMessageSummary _summaryFromRow(db.MessageSummary row) {
    return MailMessageSummary(
      id: row.id,
      folderId: row.folderId,
      subject: row.subject,
      sender: row.sender,
      preview: row.preview,
      receivedAt: row.receivedAt,
      isRead: row.pendingReadState ?? row.isRead,
      hasAttachments: row.hasAttachments,
      sequence: row.sequence,
      isImportant: row.isImportant,
      isPinned: row.isPinned,
    );
  }

  List<MailMessageSummary> _sortSummaries(List<MailMessageSummary> messages) {
    final sorted = [...messages];
    sorted.sort((left, right) {
      final pinnedComparison = (right.isPinned ? 1 : 0).compareTo(
        left.isPinned ? 1 : 0,
      );
      if (pinnedComparison != 0) {
        return pinnedComparison;
      }
      return right.receivedAt.compareTo(left.receivedAt);
    });
    return sorted;
  }

  bool? _nextPendingReadState(
    MailMessageSummary message,
    Map<String, db.MessageSummary> existingById,
  ) {
    final pending = existingById[message.id]?.pendingReadState;
    if (pending == null || pending == message.isRead) {
      return null;
    }
    return pending;
  }

  Future<void> _updateCachedSummary({
    required String accountId,
    required String messageId,
    required db.MessageSummariesCompanion companion,
  }) async {
    await (_appDatabase.update(_appDatabase.messageSummaries)..where(
          (table) =>
              table.accountId.equals(accountId) & table.id.equals(messageId),
        ))
        .write(companion);
  }

  MailMessageDetail _detailFromRow(db.MessageDetail row) {
    return MailMessageDetail(
      id: row.id,
      subject: row.subject,
      sender: row.sender,
      recipients: _splitRecipients(row.recipients),
      bodyPlain: row.bodyPlain,
      bodyHtml: row.bodyHtml,
      receivedAt: row.receivedAt,
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

  Future<String?> _authToken(String accountId) async {
    final client = _backendMailApiClient;
    final storage = _secureStorageService;
    if (client == null || storage == null) {
      return null;
    }
    final token = await storage.readAuthToken(accountId);
    if (token == null || token.trim().isEmpty) {
      return null;
    }
    return token;
  }

  Future<String> _folderPathForMessage(String accountId, String id) async {
    final summary =
        await (_appDatabase.select(_appDatabase.messageSummaries)..where(
              (table) =>
                  table.id.equals(id) & table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    if (summary != null) {
      final folder =
          await (_appDatabase.select(_appDatabase.mailFolders)..where(
                (table) =>
                    table.id.equals(summary.folderId) &
                    table.accountId.equals(accountId),
              ))
              .getSingleOrNull();
      if (folder != null) {
        return folder.path;
      }
    }
    return _folderSlugFromMessageId(accountId, id) ?? 'INBOX';
  }

  String _folderId(String accountId, String path) {
    final normalizedPath = path.trim().toLowerCase();
    return '$accountId:$normalizedPath';
  }

  String _messageId(String accountId, String folderPath, String uid) {
    final normalizedPath = folderPath.trim().toLowerCase();
    return '$accountId:$normalizedPath:api:$uid';
  }

  String? _uidFromMessageId(String messageId) {
    const marker = ':api:';
    final markerIndex = messageId.lastIndexOf(marker);
    if (markerIndex == -1) {
      return null;
    }
    final uid = messageId.substring(markerIndex + marker.length).trim();
    return uid.isEmpty ? null : uid;
  }

  String? _folderSlugFromMessageId(String accountId, String messageId) {
    const marker = ':api:';
    final prefix = '$accountId:';
    if (!messageId.startsWith(prefix)) {
      return null;
    }
    final markerIndex = messageId.lastIndexOf(marker);
    if (markerIndex == -1) {
      return null;
    }
    final folder = messageId.substring(prefix.length, markerIndex).trim();
    return folder.isEmpty ? null : folder;
  }

  bool _isInboxPath(String path) => path.trim().toLowerCase() == 'inbox';

  bool _hasFlag(List<String> flags, String flag) {
    return flags.any((value) => value.toLowerCase() == flag.toLowerCase());
  }

  String _subject(String subject) {
    final trimmed = subject.trim();
    return trimmed.isEmpty ? '(No subject)' : trimmed;
  }

  String _sender(String sender) {
    final trimmed = sender.trim();
    return trimmed.isEmpty ? 'unknown sender' : trimmed;
  }

  String _preview(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 140) {
      return collapsed;
    }
    return '${collapsed.substring(0, 140)}...';
  }

  String _folderLabel(domain.MailFolder folder) {
    return folder.name.trim().isEmpty ? folder.path : folder.name;
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

  String? _normalizeAddressish(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final emailMatch = RegExp(
      r"[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+",
      caseSensitive: false,
    ).firstMatch(trimmed);
    return emailMatch?.group(0)?.toLowerCase() ?? trimmed;
  }
}
