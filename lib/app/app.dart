import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/mailbox/presentation/mailbox_controller.dart';
import '../features/notifications/data/mail_notification_payload.dart';
import '../features/notifications/presentation/in_app_mail_notification_controller.dart';
import '../features/notifications/presentation/in_app_mail_notification_host.dart';
import 'providers.dart';
import 'router/app_route.dart';
import 'router/app_router.dart';

class FinestarMailApp extends ConsumerStatefulWidget {
  const FinestarMailApp({super.key});

  @override
  ConsumerState<FinestarMailApp> createState() => _FinestarMailAppState();
}

class _FinestarMailAppState extends ConsumerState<FinestarMailApp>
    with WidgetsBindingObserver {
  bool _notificationListenersStarted = false;
  Future<void>? _deviceRegistration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(deviceRegistrationConfigProvider, (_, next) {
      final config = next.asData?.value;
      if (config == null || !config.isConfigured) {
        return;
      }
      _startNotificationListeners();
      _registerAllDevices();
    }, fireImmediately: true);
    ref.listenManual(accountsProvider, (_, next) {
      if (next.hasValue) {
        _registerAllDevices();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncInboxForPayload(const MailNotificationPayload());
      ref.invalidate(accountSummariesProvider);
    }
  }

  void _startNotificationListeners() {
    if (_notificationListenersStarted) {
      return;
    }
    _notificationListenersStarted = true;
    ref.listenManual(fcmTokenRefreshProvider, (_, next) {
      if (!next.hasValue) {
        return;
      }
      _registerAllDevices();
    });
    ref.listenManual(fcmMessageOpenedProvider, (_, next) {
      final message = next.asData?.value;
      if (message != null) {
        _handleNotificationMessage(message, openMessage: true);
      }
    });
    ref.listenManual(fcmForegroundMessageProvider, (_, next) {
      final message = next.asData?.value;
      if (message != null) {
        _handleNotificationMessage(message, openMessage: false);
      }
    });
    ref
        .read(localNotificationServiceProvider)
        .initialize(onPayloadSelected: _handleLocalNotificationPayload);
    Future.microtask(_openInitialNotification);
  }

  Future<void> _registerAllDevices() {
    final existing = _deviceRegistration;
    if (existing != null) {
      return existing;
    }

    final config = ref.read(deviceRegistrationConfigProvider).asData?.value;
    if (config == null || !config.isConfigured) {
      return Future.value();
    }

    final registration = ref
        .read(accountsProvider.future)
        .then<void>((accounts) async {
          if (accounts.isEmpty) {
            return;
          }
          await ref
              .read(deviceRegistrationServiceProvider)
              .registerAccounts(accounts);
        })
        .whenComplete(() {
          _deviceRegistration = null;
        });
    _deviceRegistration = registration;
    return registration;
  }

  Future<void> _openInitialNotification() async {
    final message = await ref
        .read(firebaseMessagingProvider)
        .getInitialMessage();
    if (message != null) {
      await _handleNotificationMessage(message, openMessage: true);
    }
  }

  Future<void> _handleLocalNotificationPayload(String? rawPayload) async {
    final payload =
        MailNotificationPayload.fromLocalPayload(rawPayload) ??
        const MailNotificationPayload();
    await _handleNotificationPayload(payload, openMessage: true);
  }

  Future<void> _handleNotificationMessage(
    RemoteMessage message, {
    required bool openMessage,
  }) {
    return _handleNotificationPayload(
      MailNotificationPayload.fromRemoteMessage(message),
      openMessage: openMessage,
    );
  }

  Future<void> _handleNotificationPayload(
    MailNotificationPayload payload, {
    required bool openMessage,
  }) async {
    final targetAccount = await ref
        .read(notificationMailSyncServiceProvider)
        .accountForPayload(payload);
    await _syncInboxForPayload(payload);
    ref.invalidate(accountSummariesProvider);

    if (!openMessage) {
      ref
          .read(inAppMailNotificationControllerProvider.notifier)
          .showMailBanner(payload, account: targetAccount);
      return;
    }

    if (targetAccount == null) {
      if (openMessage) {
        ref.read(appRouterProvider).go(AppRoute.inbox.path);
      }
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .setActiveAccount(targetAccount.id);

    if (!mounted) {
      return;
    }

    ref.invalidate(activeAccountProvider);
    ref.invalidate(foldersProvider);
    ref.invalidate(mailboxConversationsControllerProvider);
    ref.invalidate(mailboxMessagesControllerProvider);
    ref.read(appRouterProvider).go(AppRoute.inbox.path);
  }

  Future<bool> _syncInboxForPayload(MailNotificationPayload payload) {
    return ref
        .read(notificationMailSyncServiceProvider)
        .syncInboxForPayload(payload)
        .then((synced) {
          if (synced && mounted) {
            ref.invalidate(mailboxConversationsControllerProvider);
            ref.invalidate(mailboxMessagesControllerProvider);
          }
          return synced;
        });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FS Mail',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) =>
          InAppMailNotificationHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
