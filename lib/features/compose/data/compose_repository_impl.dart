import 'dart:io';

import 'package:drift/drift.dart';
import 'package:logger/logger.dart';

import '../../../core/result/result.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/backend_mail_api_client.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
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
  static const _maxAttachmentBytes = 10 * 1024 * 1024;
  static const _maxTotalAttachmentBytes = 25 * 1024 * 1024;

  @override
  Future<Result<void>> send(OutgoingMessage message) async {
    if (message.to.isEmpty || message.subject.trim().isEmpty) {
      return const Failure<void>('Recipient and subject are required.');
    }
    final normalizedTo = _normalizeRecipients(message.to);
    final normalizedCc = _normalizeRecipients(message.cc);
    final normalizedBcc = _normalizeRecipients(message.bcc);
    if (normalizedTo == null ||
        normalizedTo.isEmpty ||
        normalizedCc == null ||
        normalizedBcc == null) {
      return const Failure<void>(
        'Recipient addresses must be valid email addresses.',
      );
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(message.accountId))).getSingleOrNull();
    final token = await _secureStorageService.readAuthToken(message.accountId);
    if (account == null || token == null || token.trim().isEmpty) {
      return const Failure<void>('Active account session is missing.');
    }

    final attachmentResult = await _backendAttachments(message.attachments);
    if (attachmentResult is Failure<List<BackendSendAttachment>>) {
      return Failure<void>(attachmentResult.message);
    }
    final attachments =
        (attachmentResult as Success<List<BackendSendAttachment>>).value;

    try {
      final response = await _backendMailApiClient.send(
        token: token,
        request: BackendSendRequest(
          to: normalizedTo,
          cc: normalizedCc,
          bcc: normalizedBcc,
          subject: message.subject,
          textBody: message.body,
          htmlBody: '',
          replyTo: null,
          fromDisplayName: account.displayName,
          forwardSourceMessage: message.forwardSourceMessage == null
              ? null
              : BackendForwardSourceMessage(
                  folder: message.forwardSourceMessage!.folder,
                  uid: message.forwardSourceMessage!.uid,
                  attachmentIds: message.forwardSourceMessage!.attachmentIds,
                ),
        ),
        attachments: attachments,
      );
      await _cacheSentMessage(
        account: account,
        message: message,
        recipients: [...normalizedTo, ...normalizedCc, ...normalizedBcc],
        backendMessageId: response.messageId,
      );

      _logger.i(
        'Sent backend message to ${normalizedTo.join(', ')} from ${message.accountId}',
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

  Future<Result<List<BackendSendAttachment>>> _backendAttachments(
    List<AttachmentRef> attachments,
  ) async {
    var totalBytes = 0;
    final backendAttachments = <BackendSendAttachment>[];
    for (final attachment in attachments) {
      if (attachment.sizeBytes > _maxAttachmentBytes) {
        return const Failure<List<BackendSendAttachment>>(
          'Each attachment must be 10 MB or smaller.',
        );
      }
      totalBytes += attachment.sizeBytes;
      if (totalBytes > _maxTotalAttachmentBytes) {
        return const Failure<List<BackendSendAttachment>>(
          'Attachments must be 25 MB or smaller in total.',
        );
      }
      final file = File(attachment.filePath);
      if (!await file.exists()) {
        return Failure<List<BackendSendAttachment>>(
          'Attachment file not found: ${attachment.fileName}',
        );
      }
      backendAttachments.add(
        BackendSendAttachment(
          filename: attachment.fileName,
          contentType: attachment.mimeType,
          bytes: await file.readAsBytes(),
        ),
      );
    }
    return Success<List<BackendSendAttachment>>(backendAttachments);
  }

  Future<void> _cacheSentMessage({
    required Account account,
    required OutgoingMessage message,
    required List<String> recipients,
    required String? backendMessageId,
  }) async {
    final sentPath = await _sentFolderPath(account.id);
    final sentFolderId = _folderId(account.id, sentPath);
    final sentAt = DateTime.now();
    final localMessageId =
        '${account.id}:${sentPath.trim().toLowerCase()}:local:${sentAt.microsecondsSinceEpoch}';

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

  List<String>? _normalizeRecipients(List<String> recipients) {
    final normalized = <String>[];
    for (final recipient in recipients) {
      final normalizedRecipient = _normalizeRecipient(recipient);
      if (normalizedRecipient == null) {
        return null;
      }
      normalized.add(normalizedRecipient);
    }
    return normalized;
  }

  String? _normalizeRecipient(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty ||
        trimmed.contains(',') ||
        trimmed.contains(';') ||
        trimmed.contains('\n') ||
        trimmed.contains('\r')) {
      return null;
    }

    if (trimmed.contains('<') || trimmed.contains('>')) {
      final openIndex = trimmed.indexOf('<');
      final closeIndex = trimmed.indexOf('>');
      final hasExactlyOnePair =
          openIndex == trimmed.lastIndexOf('<') &&
          closeIndex == trimmed.lastIndexOf('>');
      if (!hasExactlyOnePair ||
          openIndex <= 0 ||
          closeIndex <= openIndex + 1 ||
          trimmed.substring(closeIndex + 1).trim().isNotEmpty) {
        return null;
      }
      final address = trimmed.substring(openIndex + 1, closeIndex).trim();
      return _isValidEmail(address) ? address : null;
    }

    if (trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    return _isValidEmail(trimmed) ? trimmed : null;
  }

  bool _isValidEmail(String value) {
    return RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
      r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
      r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
    ).hasMatch(value);
  }
}
