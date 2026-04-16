import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import 'mail_notification_payload.dart';

class LocalNotificationService {
  LocalNotificationService({
    required FlutterLocalNotificationsPlugin plugin,
    Logger? logger,
  }) : _plugin = plugin,
       _logger = logger;

  static const AndroidNotificationChannel mailChannel =
      AndroidNotificationChannel(
        'mail_notifications',
        'Mail notifications',
        description: 'Incoming mail notifications',
        importance: Importance.high,
      );

  final FlutterLocalNotificationsPlugin _plugin;
  final Logger? _logger;
  bool _initialized = false;

  Future<void> initialize({
    void Function(String? payload)? onPayloadSelected,
  }) async {
    if (_initialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_finestar'),
    );
    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        onPayloadSelected?.call(response.payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(mailChannel);
    _initialized = true;
    _logger?.i('Local notification channel initialized.');
  }

  Future<void> showForegroundMessage(RemoteMessage message) async {
    await initialize();

    final notification = message.notification;
    final title =
        notification?.title ??
        message.data['sender'] ??
        message.data['title'] ??
        'New mail';
    final body =
        notification?.body ??
        message.data['subject'] ??
        message.data['body'] ??
        'You have a new message.';

    await _plugin.show(
      id: _notificationId(message),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'mail_notifications',
          'Mail notifications',
          channelDescription: 'Incoming mail notifications',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.email,
          icon: '@drawable/ic_stat_finestar',
          largeIcon: DrawableResourceAndroidBitmap('notification_large_icon'),
          color: Color(0xFF001F5B),
        ),
      ),
      payload: MailNotificationPayload.fromRemoteMessage(message).encode(),
    );
    _logger?.i('Displayed foreground mail notification: $title');
  }

  int _notificationId(RemoteMessage message) {
    final source =
        message.messageId ??
        message.data['messageId'] ??
        DateTime.now().microsecondsSinceEpoch.toString();
    return source.hashCode.abs() % 0x7fffffff;
  }
}
