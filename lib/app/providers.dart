import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../data/local/app_database.dart';
import '../data/remote/mail_connection_tester.dart';
import '../data/secure/secure_storage_service.dart';
import '../features/attachments/data/attachment_repository_impl.dart';
import '../features/attachments/domain/repositories/attachment_repository.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/compose/data/compose_repository_impl.dart';
import '../features/compose/domain/repositories/compose_repository.dart';
import '../features/mailbox/data/mailbox_repository_impl.dart';
import '../features/mailbox/domain/repositories/mailbox_repository.dart';
import '../features/settings/data/settings_repository_impl.dart';
import '../features/settings/domain/repositories/settings_repository.dart';

final loggerProvider = Provider<Logger>((ref) {
  return Logger(printer: PrettyPrinter(methodCount: 0));
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final mailConnectionTesterProvider = Provider<MailConnectionTester>((ref) {
  return MailConnectionTester(ref.watch(loggerProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    secureStorageService: ref.watch(secureStorageServiceProvider),
    mailConnectionTester: ref.watch(mailConnectionTesterProvider),
    appDatabase: ref.watch(appDatabaseProvider),
  );
});

final mailboxRepositoryProvider = Provider<MailboxRepository>((ref) {
  return MailboxRepositoryImpl(
    appDatabase: ref.watch(appDatabaseProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
  );
});

final composeRepositoryProvider = Provider<ComposeRepository>((ref) {
  return ComposeRepositoryImpl(
    appDatabase: ref.watch(appDatabaseProvider),
    logger: ref.watch(loggerProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(
    authRepository: ref.watch(authRepositoryProvider),
  );
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepositoryImpl();
});
