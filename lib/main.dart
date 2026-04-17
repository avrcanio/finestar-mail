import 'dart:ui';

import 'package:finestar_mail/data/local/app_database.dart';
import 'package:finestar_mail/data/remote/backend_mail_api_client.dart';
import 'package:finestar_mail/data/secure/secure_storage_service.dart';
import 'package:finestar_mail/features/mailbox/data/mailbox_repository_impl.dart';
import 'package:finestar_mail/features/notifications/data/device_registration_service.dart';
import 'package:finestar_mail/features/notifications/data/mail_notification_payload.dart';
import 'package:finestar_mail/features/notifications/data/notification_mail_sync_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  final database = AppDatabase();
  final secureStorageService = SecureStorageService();
  final httpClient = http.Client();
  try {
    final backendMailApiClient = BackendMailApiClient(
      httpClient: httpClient,
      baseUrlLoader: () async {
        final config = await const DeviceRegistrationConfigLoader().load();
        return config.apiBaseUrl;
      },
    );
    final mailboxRepository = MailboxRepositoryImpl(
      appDatabase: database,
      secureStorageService: secureStorageService,
      backendMailApiClient: backendMailApiClient,
    );
    final syncService = NotificationMailSyncService(
      activeAccountLoader: () => loadActiveMailAccount(
        database: database,
        secureStorageService: secureStorageService,
      ),
      accountsLoader: () => loadMailAccounts(database: database),
      mailboxRepository: mailboxRepository,
    );
    await syncService.syncInboxForPayload(
      MailNotificationPayload.fromRemoteMessage(message),
    );
  } catch (error) {
    debugPrint('Background notification inbox sync failed: $error');
  } finally {
    httpClient.close();
    await database.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: FinestarMailApp()));
}
