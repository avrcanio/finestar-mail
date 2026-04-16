import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:finestar_mail/core/widgets/app_scaffold.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';

import '../../../app/router/app_route.dart';
import '../../auth/presentation/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(currentAccountProvider);

    return AppScaffold(
      title: 'Account',
      child: accountAsync.when(
        data: (account) {
          if (account == null) {
            return const Center(child: Text('No active account.'));
          }

          return ListView(
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(account.email),
                    const SizedBox(height: 12),
                    Text(
                      'IMAP: ${account.connectionSettings.imapHost}:${account.connectionSettings.imapPort}',
                    ),
                    Text(
                      'SMTP: ${account.connectionSettings.smtpHost}:${account.connectionSettings.smtpPort}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  ref.invalidate(currentAccountProvider);
                  if (context.mounted) {
                    context.go(AppRoute.login.path);
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
        error: (error, stackTrace) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
