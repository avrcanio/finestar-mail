import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_route.dart';
import '../../auth/domain/entities/mail_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/data/push_notification_service.dart';

const _screenBackground = Color(0xFFF7F8FC);
const _primary = Color(0xFF153B52);
const _mutedText = Color(0xFF5D636B);
const _softBlue = Color(0xFFCFE7FA);
const _avatarBlue = Color(0xFFE8EFF8);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final activeAccountAsync = ref.watch(activeAccountProvider);
    final pushStatus = ref.watch(pushRegistrationStatusProvider);

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsTopBar(
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoute.inbox.path);
                }
              },
              onAdd: () => context.push(AppRoute.login.path),
            ),
            Expanded(
              child: accountsAsync.when(
                data: (accounts) {
                  final activeAccount = activeAccountAsync.asData?.value;
                  if (accounts.isEmpty) {
                    return _EmptyAccountsView(
                      onAdd: () => context.push(AppRoute.login.path),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                    children: [
                      for (final account in accounts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _AccountCard(
                            account: account,
                            isActive: account.id == activeAccount?.id,
                            onTap: () => _setActiveAccount(
                              context: context,
                              ref: ref,
                              account: account,
                            ),
                            onRemove: () => _removeAccount(
                              context: context,
                              ref: ref,
                              account: account,
                              accountCount: accounts.length,
                            ),
                          ),
                        ),
                      _PushNotificationsCard(
                        status: pushStatus,
                        activeAccount: activeAccount,
                        onRetry: activeAccount == null
                            ? null
                            : () => ref
                                  .read(pushNotificationServiceProvider)
                                  .registerAccount(activeAccount),
                      ),
                      const SizedBox(height: 10),
                      _AddAccountButton(
                        label: 'Add another account',
                        onPressed: () => context.push(AppRoute.login.path),
                      ),
                    ],
                  );
                },
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error.toString(), textAlign: TextAlign.center),
                  ),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setActiveAccount({
    required BuildContext context,
    required WidgetRef ref,
    required MailAccount account,
  }) async {
    await ref
        .read(authControllerProvider.notifier)
        .setActiveAccount(account.id);
    ref.invalidate(accountsProvider);
    ref.invalidate(activeAccountProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account.email} is now active.')),
      );
    }
  }

  Future<void> _removeAccount({
    required BuildContext context,
    required WidgetRef ref,
    required MailAccount account,
    required int accountCount,
  }) async {
    await ref.read(authControllerProvider.notifier).removeAccount(account.id);
    ref.invalidate(accountsProvider);
    ref.invalidate(activeAccountProvider);
    if (context.mounted && accountCount == 1) {
      context.go(AppRoute.login.path);
    }
  }
}

class _PushNotificationsCard extends StatelessWidget {
  const _PushNotificationsCard({
    required this.status,
    required this.activeAccount,
    required this.onRetry,
  });

  final PushRegistrationStatus status;
  final MailAccount? activeAccount;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = _statusColor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: .14),
                child: Icon(_statusIcon(), color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Push notifications',
                      style: textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF202124),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeAccount == null
                          ? 'Select or add an account first.'
                          : status.message,
                      style: textTheme.bodyMedium?.copyWith(
                        color: _mutedText,
                        fontSize: 14,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Retry push registration',
                onPressed: onRetry,
                color: _mutedText,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor() {
    return switch (status.state) {
      PushRegistrationState.success => const Color(0xFF137333),
      PushRegistrationState.failure => const Color(0xFFC5221F),
      PushRegistrationState.skipped => const Color(0xFFB06000),
      PushRegistrationState.registering => _primary,
      PushRegistrationState.idle => _mutedText,
    };
  }

  IconData _statusIcon() {
    return switch (status.state) {
      PushRegistrationState.success => Icons.notifications_active_outlined,
      PushRegistrationState.failure => Icons.error_outline,
      PushRegistrationState.skipped => Icons.notifications_paused_outlined,
      PushRegistrationState.registering => Icons.sync,
      PushRegistrationState.idle => Icons.notifications_none_outlined,
    };
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.onBack, required this.onAdd});

  final VoidCallback onBack;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Color(0xFF202124)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Accounts',
              style: textTheme.headlineMedium?.copyWith(
                fontFamily: textTheme.bodyLarge?.fontFamily,
                color: const Color(0xFF202124),
                fontSize: 28,
                fontWeight: FontWeight.w500,
                letterSpacing: .4,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add account',
            onPressed: onAdd,
            icon: const Icon(Icons.add, color: Color(0xFF202124)),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.isActive,
    required this.onTap,
    required this.onRemove,
  });

  final MailAccount account;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isActive ? _primary : _avatarBlue,
                child: Icon(
                  isActive
                      ? Icons.check_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isActive ? Colors.white : _primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            account.displayName.trim().isEmpty
                                ? account.email
                                : account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF202124),
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .25,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          const _ActivePill(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: _mutedText,
                        fontSize: 14,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove account',
                onPressed: onRemove,
                color: _mutedText,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _avatarBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          'Active',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .25,
          ),
        ),
      ),
    );
  }
}

class _EmptyAccountsView extends StatelessWidget {
  const _EmptyAccountsView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 32,
              backgroundColor: _avatarBlue,
              child: Icon(Icons.person_add_alt_1_outlined, color: _primary),
            ),
            const SizedBox(height: 16),
            Text(
              'No accounts yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF202124),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a mailbox to start reading and sending mail.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _mutedText, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _AddAccountButton(label: 'Add account', onPressed: onAdd),
          ],
        ),
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _softBlue,
        foregroundColor: _primary,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: .12),
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontSize: 15, letterSpacing: .35),
      ),
      icon: const Icon(Icons.add),
      label: Text(label),
    );
  }
}
