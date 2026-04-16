import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:finestar_mail/core/widgets/app_scaffold.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:finestar_mail/core/widgets/state_views.dart';

import '../../../app/router/app_route.dart';
import '../../compose/domain/entities/reply_context.dart';
import 'mailbox_controller.dart';

class MessageDetailScreen extends ConsumerWidget {
  const MessageDetailScreen({super.key, required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageAsync = ref.watch(messageDetailProvider(messageId));

    return AppScaffold(
      title: 'Message',
      child: messageAsync.when(
        data: (message) => ListView(
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.subject,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('From: ${message.sender}'),
                  const SizedBox(height: 4),
                  Text('To: ${message.recipients.join(', ')}'),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM d, y HH:mm').format(message.receivedAt)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(child: Text(message.bodyPlain)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    AppRoute.compose.path,
                    extra: ReplyContext(
                      messageId: message.id,
                      subject: message.subject,
                      action: ReplyAction.reply,
                      recipients: [message.sender],
                    ),
                  ),
                  icon: const Icon(Icons.reply_outlined),
                  label: const Text('Reply'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    AppRoute.compose.path,
                    extra: ReplyContext(
                      messageId: message.id,
                      subject: message.subject,
                      action: ReplyAction.replyAll,
                      recipients: [message.sender, ...message.recipients],
                    ),
                  ),
                  icon: const Icon(Icons.reply_all_outlined),
                  label: const Text('Reply all'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                    AppRoute.compose.path,
                    extra: ReplyContext(
                      messageId: message.id,
                      subject: message.subject,
                      action: ReplyAction.forward,
                      recipients: const [],
                    ),
                  ),
                  icon: const Icon(Icons.forward_to_inbox_outlined),
                  label: const Text('Forward'),
                ),
              ],
            ),
          ],
        ),
        error: (error, stackTrace) => ErrorStateView(message: error.toString()),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
