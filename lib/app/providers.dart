import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/local/app_database.dart';
import '../data/remote/backend_mail_api_client.dart';
import '../data/secure/secure_storage_service.dart';
import '../features/attachments/data/attachment_repository_impl.dart';
import '../features/attachments/domain/repositories/attachment_repository.dart';
import '../features/auth/data/backend_auth_token_selector.dart';
import '../features/auth/data/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/contacts/data/contacts_repository_impl.dart';
import '../features/contacts/domain/repositories/contacts_repository.dart';
import '../features/compose/data/compose_repository_impl.dart';
import '../features/compose/data/openai_compose_assist_service.dart';
import '../features/compose/domain/repositories/compose_repository.dart';
import '../features/mailbox/data/mailbox_repository_impl.dart';
import '../features/mailbox/domain/repositories/mailbox_repository.dart';
import '../features/notifications/data/device_registration_service.dart';
import '../features/notifications/data/local_notification_service.dart';
import '../features/notifications/data/notification_mail_sync_service.dart';
import '../features/settings/data/account_summaries_repository.dart';
import '../features/settings/data/settings_repository_impl.dart';
import '../features/settings/domain/entities/account_summary.dart';
import '../features/settings/domain/repositories/settings_repository.dart';
import '../core/platform/share_intent_service.dart';
import '../core/platform/document_scanner_service.dart';

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

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    secureStorageService: ref.watch(secureStorageServiceProvider),
    backendMailApiClient: ref.watch(backendMailApiClientProvider),
    appDatabase: ref.watch(appDatabaseProvider),
  );
});

final mailboxRepositoryProvider = Provider<MailboxRepository>((ref) {
  return MailboxRepositoryImpl(
    appDatabase: ref.watch(appDatabaseProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
    backendMailApiClient: ref.watch(backendMailApiClientProvider),
  );
});

final composeRepositoryProvider = Provider<ComposeRepository>((ref) {
  return ComposeRepositoryImpl(
    appDatabase: ref.watch(appDatabaseProvider),
    logger: ref.watch(loggerProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
    backendMailApiClient: ref.watch(backendMailApiClientProvider),
  );
});

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepositoryImpl(
    backendMailApiClient: ref.watch(backendMailApiClientProvider),
    backendAuthTokenSelector: ref.watch(backendAuthTokenSelectorProvider),
    logger: ref.watch(loggerProvider),
  );
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(
    authRepository: ref.watch(authRepositoryProvider),
  );
});

final backendAuthTokenSelectorProvider = Provider<BackendAuthTokenSelector>((
  ref,
) {
  return BackendAuthTokenSelector(
    authRepository: ref.watch(authRepositoryProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
  );
});

final accountSummariesRepositoryProvider = Provider<AccountSummariesRepository>(
  (ref) {
    return AccountSummariesRepository(
      backendMailApiClient: ref.watch(backendMailApiClientProvider),
      backendAuthTokenSelector: ref.watch(backendAuthTokenSelectorProvider),
      fcmTokenLoader: ref.watch(firebaseMessagingProvider).getToken,
      logger: ref.watch(loggerProvider),
    );
  },
);

final accountSummariesProvider = FutureProvider<Map<String, AccountSummary>>((
  ref,
) {
  return ref.watch(accountSummariesRepositoryProvider).fetchSummariesByEmail();
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepositoryImpl();
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final backendMailApiClientProvider = Provider<BackendMailApiClient>((ref) {
  return BackendMailApiClient(
    httpClient: ref.watch(httpClientProvider),
    baseUrlLoader: () async {
      final config = await ref.read(deviceRegistrationConfigProvider.future);
      return config.apiBaseUrl;
    },
  );
});

final deviceRegistrationConfigProvider =
    FutureProvider<DeviceRegistrationConfig>((ref) {
      return const DeviceRegistrationConfigLoader().load();
    });

final firebaseMessagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

final fcmTokenRefreshProvider = StreamProvider<String>((ref) {
  return ref.watch(firebaseMessagingProvider).onTokenRefresh;
});

final fcmMessageOpenedProvider = StreamProvider<RemoteMessage>((ref) {
  return FirebaseMessaging.onMessageOpenedApp;
});

final fcmForegroundMessageProvider = StreamProvider<RemoteMessage>((ref) {
  return FirebaseMessaging.onMessage;
});

final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      return FlutterLocalNotificationsPlugin();
    });

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return LocalNotificationService(
    plugin: ref.watch(flutterLocalNotificationsPluginProvider),
    logger: ref.watch(loggerProvider),
  );
});

final notificationMailSyncServiceProvider =
    Provider<NotificationMailSyncService>((ref) {
      return NotificationMailSyncService(
        activeAccountLoader: () =>
            ref.read(authRepositoryProvider).getActiveAccount(),
        accountsLoader: () => ref.read(authRepositoryProvider).getAccounts(),
        mailboxRepository: ref.watch(mailboxRepositoryProvider),
        logger: ref.watch(loggerProvider),
      );
    });

final shareIntentServiceProvider = Provider<ShareIntentService>((ref) {
  return ShareIntentService();
});

final documentScannerServiceProvider = Provider<DocumentScannerService>((ref) {
  return DocumentScannerService();
});

final openAiComposeAssistServiceProvider =
    Provider<OpenAiComposeAssistService>((ref) {
  return OpenAiComposeAssistService(
    apiKey: kOpenAiApiKeyFromEnvironment,
    httpClient: ref.watch(httpClientProvider),
  );
});

final deviceRegistrationServiceProvider = Provider<DeviceRegistrationService>((
  ref,
) {
  final messaging = ref.watch(firebaseMessagingProvider);
  return DeviceRegistrationService(
    config:
        ref.watch(deviceRegistrationConfigProvider).asData?.value ??
        DeviceRegistrationConfig.fromEnvironment(),
    httpClient: ref.watch(httpClientProvider),
    fcmTokenLoader: messaging.getToken,
    authTokenLoader: ref.watch(secureStorageServiceProvider).readAuthToken,
    permissionRequester: () async {
      await messaging.requestPermission();
    },
    appVersionLoader: () async {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    },
    platform: 'android',
    logger: ref.watch(loggerProvider),
  );
});
