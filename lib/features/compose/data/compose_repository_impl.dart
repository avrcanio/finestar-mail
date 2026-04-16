import 'package:drift/drift.dart';
import 'package:enough_mail/imap.dart';
import 'package:enough_mail/smtp.dart';
import 'package:logger/logger.dart';

import '../../../core/result/result.dart';
import '../../../data/local/app_database.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/outgoing_message.dart';
import '../domain/entities/reply_context.dart';
import '../domain/repositories/compose_repository.dart';

class ComposeRepositoryImpl implements ComposeRepository {
  ComposeRepositoryImpl({
    required AppDatabase appDatabase,
    required Logger logger,
    required SecureStorageService secureStorageService,
  }) : _appDatabase = appDatabase,
       _logger = logger,
       _secureStorageService = secureStorageService;

  final AppDatabase _appDatabase;
  final Logger _logger;
  final SecureStorageService _secureStorageService;

  @override
  Future<Result<void>> send(OutgoingMessage message) async {
    if (message.to.isEmpty || message.subject.trim().isEmpty) {
      return const Failure<void>('Recipient and subject are required.');
    }

    final account = await (_appDatabase.select(
      _appDatabase.accounts,
    )..where((table) => table.id.equals(message.accountId))).getSingleOrNull();
    final password = await _secureStorageService.readPassword(
      message.accountId,
    );
    if (account == null || password == null || password.isEmpty) {
      return const Failure<void>('Active account credentials are missing.');
    }

    final smtpClient = SmtpClient('finestar_mail', isLogEnabled: false);
    try {
      await smtpClient.connectToServer(
        account.smtpHost,
        account.smtpPort,
        isSecure: account.smtpSecurity == 'sslTls',
        timeout: const Duration(seconds: 12),
      );
      await smtpClient.ehlo();
      if (account.smtpSecurity == 'startTls') {
        await smtpClient.startTls();
      }
      await smtpClient.authenticate(
        account.email,
        password,
        AuthMechanism.plain,
      );

      final mimeMessage = MessageBuilder.buildSimpleTextMessage(
        MailAddress(account.displayName, account.email),
        message.to.map((email) => MailAddress(null, email)).toList(),
        message.body,
        cc: message.cc.map((email) => MailAddress(null, email)).toList(),
        bcc: message.bcc.map((email) => MailAddress(null, email)).toList(),
        subject: message.subject,
      );
      _applyReplyHeaders(mimeMessage, message);
      await smtpClient.sendMessage(mimeMessage);
      await _appendToSentFolder(
        account: account,
        password: password,
        mimeMessage: mimeMessage,
      );
      await _cacheSentMessage(
        account: account,
        message: message,
        mimeMessage: mimeMessage,
      );

      _logger.i(
        'Sent SMTP message to ${message.to.join(', ')} from ${message.accountId}',
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      _logger.w(
        'SMTP send failed for ${message.accountId}',
        error: error,
        stackTrace: stackTrace,
      );
      return Failure<void>('Unable to send message: $error');
    } finally {
      await smtpClient.disconnect();
    }
  }

  Future<void> _appendToSentFolder({
    required Account account,
    required String password,
    required MimeMessage mimeMessage,
  }) async {
    final sentPath = await _sentFolderPath(account.id);
    final imapClient = ImapClient(isLogEnabled: false);
    try {
      await imapClient.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: account.imapSecurity == 'sslTls',
        timeout: const Duration(seconds: 12),
      );
      if (account.imapSecurity == 'startTls') {
        await imapClient.startTls();
      }
      await imapClient.login(account.email, password);
      await imapClient.appendMessage(
        mimeMessage,
        targetMailboxPath: sentPath,
        flags: const ['\\Seen'],
        responseTimeout: const Duration(seconds: 20),
      );
    } catch (error, stackTrace) {
      _logger.w(
        'Unable to append sent message to IMAP Sent folder for ${account.id}',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      await imapClient.disconnect();
    }
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

  Future<void> _cacheSentMessage({
    required Account account,
    required OutgoingMessage message,
    required MimeMessage mimeMessage,
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
          messageIdHeader: Value(mimeMessage.getHeaderValue('Message-Id')),
          inReplyToHeader: Value(mimeMessage.getHeaderValue('In-Reply-To')),
          referencesHeader: Value(mimeMessage.getHeaderValue('References')),
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

  void _applyReplyHeaders(MimeMessage mimeMessage, OutgoingMessage message) {
    final context = message.replyContext;
    if (context == null || context.action == ReplyAction.forward) {
      return;
    }

    final originalMessageId = context.originalMessageIdHeader?.trim();
    if (originalMessageId == null || originalMessageId.isEmpty) {
      return;
    }

    mimeMessage.setHeader('In-Reply-To', originalMessageId);
    final references = [
      ...?context.originalReferencesHeader
          ?.split(RegExp(r'\s+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      originalMessageId,
    ];
    mimeMessage.setHeader('References', references.toSet().join(' '));
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
