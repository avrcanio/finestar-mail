import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_route.dart';
import '../../../core/widgets/state_views.dart';
import '../../compose/domain/entities/reply_context.dart';
import '../domain/entities/mail_message_detail.dart';
import 'mailbox_controller.dart';

const _screenBackground = Color(0xFFF7F8FC);
const _primary = Color(0xFF153B52);
const _mutedText = Color(0xFF5D636B);

class MessageDetailScreen extends ConsumerWidget {
  const MessageDetailScreen({super.key, required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageAsync = ref.watch(messageDetailProvider(messageId));

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: Column(
          children: [
            _MessageTopBar(
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoute.inbox.path);
                }
              },
            ),
            Expanded(
              child: messageAsync.when(
                data: (message) => _MessageDetailContent(message: message),
                error: (error, stackTrace) =>
                    ErrorStateView(message: error.toString()),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageTopBar extends StatelessWidget {
  const _MessageTopBar({required this.onBack});

  final VoidCallback onBack;

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
              'Message',
              style: textTheme.headlineMedium?.copyWith(
                fontFamily: textTheme.bodyLarge?.fontFamily,
                color: const Color(0xFF202124),
                fontSize: 28,
                fontWeight: FontWeight.w500,
                letterSpacing: .2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageDetailContent extends StatelessWidget {
  const _MessageDetailContent({required this.message});

  final MailMessageDetail message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      children: [
        _MessageCard(child: _MessageHeader(message: message)),
        const SizedBox(height: 16),
        _MessageCard(child: _MessageBody(body: message.bodyPlain)),
        const SizedBox(height: 18),
        _ReplyActions(message: message),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: child,
      ),
    );
  }
}

class _MessageHeader extends StatelessWidget {
  const _MessageHeader({required this.message});

  final MailMessageDetail message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.subject,
          style: textTheme.titleLarge?.copyWith(
            color: _primary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: .1,
          ),
        ),
        const SizedBox(height: 16),
        _MetaLine(label: 'From', value: message.sender),
        const SizedBox(height: 8),
        _MetaLine(label: 'To', value: message.recipients.join(', ')),
        const SizedBox(height: 8),
        Text(
          DateFormat('MMM d, y HH:mm').format(message.receivedAt),
          style: textTheme.bodyMedium?.copyWith(
            color: _mutedText,
            fontSize: 14,
            height: 1.35,
            letterSpacing: .1,
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return RichText(
      text: TextSpan(
        style: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF202124),
          fontSize: 14,
          height: 1.35,
          letterSpacing: .1,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: _mutedText),
          ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return Text(
      body,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF202124),
        fontSize: 15,
        height: 1.5,
        letterSpacing: .1,
      ),
    );
  }
}

class _ReplyActions extends StatelessWidget {
  const _ReplyActions({required this.message});

  final MailMessageDetail message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ReplyButton(
            icon: Icons.reply_outlined,
            label: 'Reply',
            onPressed: () => _openCompose(context, ReplyAction.reply),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReplyButton(
            icon: Icons.reply_all_outlined,
            label: 'Reply all',
            onPressed: () => _openCompose(context, ReplyAction.replyAll),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ReplyButton(
            icon: Icons.forward_to_inbox_outlined,
            label: 'Forward',
            onPressed: () => _openCompose(context, ReplyAction.forward),
          ),
        ),
      ],
    );
  }

  void _openCompose(BuildContext context, ReplyAction action) {
    context.push(
      AppRoute.compose.path,
      extra: ReplyContext(
        messageId: message.id,
        subject: message.subject,
        action: action,
        recipients: switch (action) {
          ReplyAction.reply => [message.sender],
          ReplyAction.replyAll => [message.sender, ...message.recipients],
          ReplyAction.forward => const [],
        },
      ),
    );
  }
}

class _ReplyButton extends StatelessWidget {
  const _ReplyButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: const BorderSide(color: _mutedText),
        shape: const StadiumBorder(),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: .05,
        ),
      ),
      icon: Icon(icon, size: 16),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
  }
}
