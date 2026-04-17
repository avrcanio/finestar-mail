import 'package:logger/logger.dart';

import '../../../data/local/app_database.dart';
import '../../../data/secure/secure_storage_service.dart';
import '../../auth/domain/entities/connection_settings.dart';
import '../../auth/domain/entities/mail_account.dart';
import '../../mailbox/domain/repositories/mailbox_repository.dart';
import 'mail_notification_payload.dart';

class NotificationMailSyncService {
  NotificationMailSyncService({
    required Future<MailAccount?> Function() activeAccountLoader,
    required Future<List<MailAccount>> Function() accountsLoader,
    required MailboxRepository mailboxRepository,
    Logger? logger,
  }) : _activeAccountLoader = activeAccountLoader,
       _accountsLoader = accountsLoader,
       _mailboxRepository = mailboxRepository,
       _logger = logger;

  final Future<MailAccount?> Function() _activeAccountLoader;
  final Future<List<MailAccount>> Function() _accountsLoader;
  final MailboxRepository _mailboxRepository;
  final Logger? _logger;

  Future<MailAccount?> activeAccount() => _activeAccountLoader();

  Future<MailAccount?> accountForPayload(
    MailNotificationPayload payload,
  ) async {
    final payloadAccount = payload.accountEmail?.trim().toLowerCase();
    if (payloadAccount == null || payloadAccount.isEmpty) {
      return _activeAccountLoader();
    }

    final accounts = await _accountsLoader();
    for (final account in accounts) {
      if (_payloadMatchesAccount(payloadAccount, account)) {
        return account;
      }
    }
    return null;
  }

  Future<bool> syncInboxForPayload(MailNotificationPayload payload) async {
    final account = await accountForPayload(payload);
    if (account == null) {
      _logger?.i(
        'Skipping notification inbox sync because no matching account exists.',
      );
      return false;
    }

    try {
      await _mailboxRepository.getInbox(
        accountId: account.id,
        forceRefresh: true,
      );
      _logger?.i('Synced inbox after notification for ${account.email}.');
      return true;
    } catch (error, stackTrace) {
      _logger?.w(
        'Notification inbox sync failed for ${account.email}.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  bool _payloadMatchesAccount(String payloadAccount, MailAccount account) {
    return payloadAccount == account.email.toLowerCase() ||
        payloadAccount == account.id.toLowerCase();
  }
}

Future<List<MailAccount>> loadMailAccounts({
  required AppDatabase database,
}) async {
  final rows = await database.select(database.accounts).get();
  return rows.map(_accountFromRow).toList();
}

Future<MailAccount?> loadActiveMailAccount({
  required AppDatabase database,
  required SecureStorageService secureStorageService,
}) async {
  final rows = await database.select(database.accounts).get();
  if (rows.isEmpty) {
    await secureStorageService.clearActiveAccountId();
    return null;
  }

  final activeAccountId = await secureStorageService.readActiveAccountId();
  Account? activeRow;
  if (activeAccountId != null) {
    for (final row in rows) {
      if (row.id == activeAccountId) {
        activeRow = row;
        break;
      }
    }
  }
  return _accountFromRow(activeRow ?? rows.first);
}

MailAccount _accountFromRow(Account row) {
  return MailAccount(
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    connectionSettings: ConnectionSettings(
      imapHost: row.imapHost,
      imapPort: row.imapPort,
      imapSecurity: MailSecurity.values.byName(row.imapSecurity),
      smtpHost: row.smtpHost,
      smtpPort: row.smtpPort,
      smtpSecurity: MailSecurity.values.byName(row.smtpSecurity),
    ),
    createdAt: row.createdAt,
  );
}
