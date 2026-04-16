import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/domain/entities/mail_account.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/mailbox/presentation/mailbox_controller.dart';
import '../features/notifications/data/mail_notification_payload.dart';
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
  Future<bool>? _foregroundInboxSync;

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
      final account = ref.read(activeAccountProvider).asData?.value;
      if (account != null) {
        _registerDevice(account);
      }
    }, fireImmediately: true);
    ref.listenManual(activeAccountProvider, (_, next) {
      final account = next.asData?.value;
      if (account != null) {
        _registerDevice(account);
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
      final account = ref.read(activeAccountProvider).asData?.value;
      if (account != null) {
        _registerDevice(account);
      }
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

  Future<void> _registerDevice(MailAccount account) async {
    final config = ref.read(deviceRegistrationConfigProvider).asData?.value;
    if (config == null || !config.isConfigured) {
      return;
    }
    await ref.read(deviceRegistrationServiceProvider).registerAccount(account);
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
    await _syncInboxForPayload(payload);
    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      if (openMessage) {
        ref.read(appRouterProvider).go(AppRoute.inbox.path);
      }
      return;
    }

    if (payload.accountEmail != null &&
        payload.accountEmail!.toLowerCase() != account.email.toLowerCase()) {
      return;
    }

    if (!openMessage) {
      return;
    }

    final messageId = await ref
        .read(mailboxRepositoryProvider)
        .findCachedMessageId(
          accountId: account.id,
          localMessageId: payload.localMessageId,
          folder: payload.folder,
          uid: payload.uid,
          rfcMessageId: payload.messageId,
          subject: payload.subject,
          sender: payload.sender,
        );

    if (!mounted) {
      return;
    }

    if (messageId == null) {
      ref.read(appRouterProvider).go(AppRoute.inbox.path);
      return;
    }

    ref
        .read(appRouterProvider)
        .go(AppRoute.messageDetail.path.replaceFirst(':id', messageId));
  }

  Future<bool> _syncInboxForPayload(MailNotificationPayload payload) {
    final existingSync = _foregroundInboxSync;
    if (existingSync != null) {
      return existingSync;
    }

    final sync = ref
        .read(notificationMailSyncServiceProvider)
        .syncInboxForPayload(payload)
        .then((synced) {
          if (synced && mounted) {
            ref.invalidate(folderMessagesProvider);
          }
          return synced;
        })
        .whenComplete(() {
          _foregroundInboxSync = null;
        });
    _foregroundInboxSync = sync;
    return sync;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FS Mail',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
