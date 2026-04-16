import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/domain/entities/mail_account.dart';
import '../features/auth/presentation/auth_controller.dart';
import 'router/app_router.dart';
import 'router/app_route.dart';
import 'providers.dart';

class FinestarMailApp extends ConsumerStatefulWidget {
  const FinestarMailApp({super.key});

  @override
  ConsumerState<FinestarMailApp> createState() => _FinestarMailAppState();
}

class _FinestarMailAppState extends ConsumerState<FinestarMailApp> {
  bool _notificationHandlersStarted = false;
  String? _lastRegistrationAttemptAccountId;
  StreamSubscription? _notificationTapSubscription;

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final activeAccount = ref.watch(activeAccountProvider).asData?.value;
    if (activeAccount != null) {
      _registerAccountOnce(ref, activeAccount);
    }
    _registerActiveAccount(ref);
    _startNotificationHandlers(ref);

    return MaterialApp.router(
      title: 'FS Mail',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }

  void _registerActiveAccount(WidgetRef ref) {
    ref.listen<AsyncValue<MailAccount?>>(activeAccountProvider, (_, next) {
      final account = next.asData?.value;
      if (account != null) {
        _registerAccountOnce(ref, account);
      }
    });
  }

  void _registerAccountOnce(WidgetRef ref, MailAccount account) {
    if (_lastRegistrationAttemptAccountId == account.id) {
      return;
    }
    _lastRegistrationAttemptAccountId = account.id;
    ref.read(pushNotificationServiceProvider).registerAccount(account);
  }

  void _startNotificationHandlers(WidgetRef ref) {
    if (_notificationHandlersStarted) {
      return;
    }
    _notificationHandlersStarted = true;

    final service = ref.read(pushNotificationServiceProvider);
    if (!service.isConfigured) {
      return;
    }
    final router = ref.read(appRouterProvider);

    service.takeInitialMessage().then((message) {
      if (message != null && mounted) {
        router.go(AppRoute.inbox.path);
      }
    });

    _notificationTapSubscription = service.notificationTaps.listen((_) {
      if (mounted) {
        router.go(AppRoute.inbox.path);
      }
    });
  }
}
