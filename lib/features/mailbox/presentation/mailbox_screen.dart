import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:finestar_mail/core/widgets/app_scaffold.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:finestar_mail/core/widgets/state_views.dart';

import '../../../app/router/app_route.dart';
import 'mailbox_controller.dart';

class MailboxScreen extends ConsumerWidget {
  const MailboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    final inbox = ref.watch(inboxProvider);
    final formatter = DateFormat('MMM d, HH:mm');

    return AppScaffold(
      title: 'Inbox',
      actions: [
        IconButton(
          onPressed: () => context.push(AppRoute.settings.path),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoute.compose.path),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose'),
      ),
      child: RefreshIndicator(
        onRefresh: () => ref.read(inboxProvider.notifier).refresh(),
        child: ListView(
          children: [
            folders.when(
              data: (items) => SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      Chip(label: Text(items[index].name)),
                ),
              ),
              error: (error, stackTrace) => const SizedBox.shrink(),
              loading: () => const LinearProgressIndicator(),
            ),
            const SizedBox(height: 16),
            inbox.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const EmptyStateView(
                    title: 'No messages yet',
                    message:
                        'Once the account syncs, inbox items will appear here.',
                  );
                }

                return Column(
                  children: messages
                      .map(
                        (message) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionCard(
                            padding: const EdgeInsets.all(0),
                            child: ListTile(
                              onTap: () => context.push(
                                AppRoute.messageDetail.path.replaceFirst(
                                  ':id',
                                  message.id,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(18),
                              title: Text(
                                message.subject,
                                style: TextStyle(
                                  fontWeight: message.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${message.sender}\n${message.preview}',
                                ),
                              ),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(formatter.format(message.receivedAt)),
                                  if (message.hasAttachments)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Icon(Icons.attach_file, size: 16),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              error: (error, stackTrace) => ErrorStateView(
                message: error.toString(),
                onRetry: () => ref.read(inboxProvider.notifier).refresh(),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
