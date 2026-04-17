import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_route.dart';
import '../../../app/router/app_router.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../mailbox/presentation/mailbox_controller.dart';
import 'in_app_mail_notification_controller.dart';

class InAppMailNotificationHost extends ConsumerWidget {
  const InAppMailNotificationHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notification = ref.watch(inAppMailNotificationControllerProvider);
    return Stack(
      children: [
        child,
        if (notification != null)
          _InAppMailNotificationBanner(notification: notification),
      ],
    );
  }
}

class _InAppMailNotificationBanner extends ConsumerWidget {
  const _InAppMailNotificationBanner({required this.notification});

  final InAppMailNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          color: Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _openInbox(ref),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primary,
                    child: const Icon(
                      Icons.mail_outline,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          notification.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          notification.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF4B5563)),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Dismiss notification',
                    child: IconButton(
                      onPressed: () => ref
                          .read(
                            inAppMailNotificationControllerProvider.notifier,
                          )
                          .dismiss(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInbox(WidgetRef ref) async {
    final account = notification.account;
    if (account != null) {
      await ref
          .read(authControllerProvider.notifier)
          .setActiveAccount(account.id);
      ref.invalidate(activeAccountProvider);
      ref.invalidate(foldersProvider);
      ref.invalidate(mailboxConversationsControllerProvider);
      ref.invalidate(mailboxMessagesControllerProvider);
      ref.invalidate(accountSummariesProvider);
    }
    ref.read(inAppMailNotificationControllerProvider.notifier).dismiss();
    ref.read(appRouterProvider).go(AppRoute.inbox.path);
  }
}
