import 'package:drift/drift.dart';
import 'package:logger/logger.dart';

import '../../../core/result/result.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/backend_mail_api_client.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/outgoing_message.dart';
import '../domain/repositories/compose_repository.dart';

class ComposeRepositoryImpl implements ComposeRepository {
  ComposeRepositoryImpl({
    required AppDatabase appDatabase,
    required Logger logger,
    required SecureStorageService secureStorageService,
    required BackendMailApiClient backendMailApiClient,
  }) : _appDatabase = appDatabase,
       _logger = logger,
       _secureStorageService = secureStorageService,
       _backendMailApiClient = backendMailApiClient;

  final AppDatabase _appDatabase;
  final Logger _logger;
  final SecureStorageService _secureStorageService;
  final BackendMailApiClient _backendMailApiClient;

  @override
  Future<Result<void>> send(OutgoingMessage message) async {
    if (message.to.isEmpty || message.subject.trim().isEmpty) {
      return const Failure<void>('Recipient and subject are required.');
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(message.accountId))).getSingleOrNull();
    final token = await _secureStorageService.readAuthToken(message.accountId);
    if (account == null || token == null || token.trim().isEmpty) {
      return const Failure<void>('Active account session is missing.');
    }

    try {
      final response = await _backendMailApiClient.send(
        token: token,
        request: BackendSendRequest(
          to: message.to,
          cc: message.cc,
          bcc: message.bcc,
          subject: message.subject,
          textBody: message.body,
          htmlBody: '',
          replyTo: null,
          fromDisplayName: account.displayName,
        ),
      );
      await _cacheSentMessage(
        account: account,
        message: message,
        backendMessageId: response.messageId,
      );

      _logger.i(
        'Sent backend message to ${message.to.join(', ')} from ${message.accountId}',
      );
      return const Success<void>(null);
    } on BackendMailApiException catch (error, stackTrace) {
      _logger.w(
        'Backend send failed for ${message.accountId}',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>(error.userMessage);
    } catch (error, stackTrace) {
      _logger.w(
        'Backend send failed for ${message.accountId}',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>('Unable to send message: $error');
    }
  }

  Future<void> _cacheSentMessage({
    required Account account,
    required OutgoingMessage message,
    required String? backendMessageId,
  }) async {
    final sentPath = await _sentFolderPath(account.id);
    final sentFolderId = _folderId(account.id, sentPath);
    final sentAt = DateTime.now();
    final localMessageId =
        '${account.id}:${sentPath.trim().toLowerCase()}:local:${sentAt.microsecondsSinceEpoch}';
    final recipients = [...message.to, ...message.cc, ...message.bcc];

    await _appDatabase.batch((batch) {
      batch.insert(
        _appDatabase.mailFolders,
        MailFoldersCompanion.insert(
          id: sentFolderId,
          accountId: account.id,
          name: 'Sent',
          path: sentPath,
          isInbox: false,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      batch.insert(
        _appDatabase.messageDetails,
        MessageDetailsCompanion.insert(
          id: localMessageId,
          accountId: Value(account.id),
          subject: message.subject,
          sender: account.email,
          recipients: recipients.join(','),
          bodyPlain: message.body,
          bodyHtml: const Value(null),
          receivedAt: sentAt,
          folderId: Value(sentFolderId),
          messageIdHeader: Value(backendMessageId),
          inReplyToHeader: Value(message.replyContext?.originalMessageIdHeader),
          referencesHeader: Value(
            _referencesHeader(message.replyContext?.originalReferencesHeader),
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
      batch.insert(
        _appDatabase.messageSummaries,
        MessageSummariesCompanion.insert(
          id: localMessageId,
          accountId: Value(account.id),
          folderId: sentFolderId,
          subject: message.subject,
          sender: account.email,
          preview: _preview(message.body),
          receivedAt: sentAt,
          isRead: true,
          hasAttachments: message.attachments.isNotEmpty,
          sequence: sentAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<String> _sentFolderPath(String accountId) async {
    final folders = await (_appDatabase.select(
      _appDatabase.mailFolders,
    )..where((table) => table.accountId.equals(accountId))).get();
    for (final folder in folders) {
      final normalizedName = folder.name.trim().toLowerCase();
      final normalizedPath = folder.path.trim().toLowerCase();
      if (normalizedName == 'sent' || normalizedPath == 'sent') {
        return folder.path;
      }
    }
    return 'Sent';
  }

  String? _referencesHeader(String? originalReferencesHeader) {
    final references = originalReferencesHeader
        ?.split(RegExp(r'\s+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' ');
    return references == null || references.isEmpty ? null : references;
  }

  String _folderId(String accountId, String path) {
    final normalizedPath = path.trim().toLowerCase();
    return '$accountId:$normalizedPath';
  }

  String _preview(String body) {
    final collapsed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 140) {
      return collapsed;
    }
    return '${collapsed.substring(0, 140)}...';
  }
}
