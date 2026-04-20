import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/app_route.dart';
import '../../domain/entities/mail_conversation.dart';
import '../../domain/entities/mail_folder.dart';
import '../../domain/entities/mail_message_summary.dart';
import '../message_detail_route_result.dart';

typedef MessageActionCallback =
    Future<void> Function({
      required BuildContext context,
      required WidgetRef ref,
      required MailMessageSummary message,
      required MailFolder folder,
    });

class MailMessageListTile extends StatelessWidget {
  const MailMessageListTile({
    super.key,
    required this.message,
    required this.folder,
    required this.selected,
    required this.selectionEnabled,
    required this.selectionActive,
    required this.onToggleSelected,
    required this.onShowActions,
    this.hasAttachments,
    this.isUnread,
    this.isImportant,
    this.isPinned,
    this.replyCount = 0,
    this.direction = MailConversationDirection.inbound,
    this.displaySubject,
    this.title,
    this.showOutboundBadge = false,
    this.isLatestInConversation = false,
    this.onDeletedMessages,
  });

  final MailMessageSummary message;
  final MailFolder folder;
  final bool selected;
  final bool selectionEnabled;
  final bool selectionActive;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;
  final bool? hasAttachments;
  final bool? isUnread;
  final bool? isImportant;
  final bool? isPinned;
  final int replyCount;
  final MailConversationDirection direction;
  final String? displaySubject;
  final Widget? title;
  final bool showOutboundBadge;
  final bool isLatestInConversation;
  final ValueChanged<Set<String>>? onDeletedMessages;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d');
    final effectiveUnread = isUnread ?? !message.isRead;
    final effectiveImportant = isImportant ?? message.isImportant;
    final effectivePinned = isPinned ?? message.isPinned;
    final effectiveHasAttachments = hasAttachments ?? message.hasAttachments;

    return Consumer(
      builder: (context, ref, child) {
        return ListTile(
          key: isLatestInConversation
              ? ValueKey('latest-conversation-message-${message.id}')
              : null,
          onLongPress: () => onShowActions(
            context: context,
            ref: ref,
            message: message,
            folder: folder,
          ),
          onTap: selectionActive && selectionEnabled
              ? () => onToggleSelected(message.id)
              : () => _openDetail(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          leading: Tooltip(
            message: 'Select message',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: selectionEnabled
                  ? () => onToggleSelected(message.id)
                  : null,
              child: CircleAvatar(
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFE8EFF8),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : Text(
                        _senderInitial(message.sender),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          title:
              title ??
              _DefaultMessageTitle(
                subject: displaySubject ?? message.subject,
                isUnread: effectiveUnread,
                replyCount: replyCount,
                direction: direction,
                showOutboundBadge: showOutboundBadge,
                isLatestInConversation: isLatestInConversation,
              ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${message.sender}\n${message.preview}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: isLatestInConversation
                  ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF3C4043),
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatter.format(message.receivedAt)),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (effectiveImportant)
                    const Icon(Icons.error, size: 16, color: Color(0xFFD93025)),
                  if (effectivePinned)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: Color(0xFF153B52),
                      ),
                    ),
                  if (effectiveHasAttachments)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.attach_file, size: 16),
                    ),
                ],
              ),
            ],
          ),
          isThreeLine: true,
        );
      },
    );
  }

  String _senderInitial(String sender) {
    final trimmed = sender.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _openDetail(BuildContext context) async {
    final result = await context.push<MessageDetailRouteResult>(
      AppRoute.messageDetail.path.replaceFirst(':id', message.id),
    );
    final deletedMessageIds = result?.deletedMessageIds ?? const <String>{};
    if (deletedMessageIds.isNotEmpty && context.mounted) {
      onDeletedMessages?.call(deletedMessageIds);
    }
  }
}

class _DefaultMessageTitle extends StatelessWidget {
  const _DefaultMessageTitle({
    required this.subject,
    required this.isUnread,
    required this.replyCount,
    required this.direction,
    required this.showOutboundBadge,
    required this.isLatestInConversation,
  });

  final String subject;
  final bool isUnread;
  final int replyCount;
  final MailConversationDirection direction;
  final bool showOutboundBadge;
  final bool isLatestInConversation;

  @override
  Widget build(BuildContext context) {
    final showBadge =
        showOutboundBadge && direction == MailConversationDirection.outbound;

    return Row(
      children: [
        if (showBadge) ...[
          const OutboundMessageBadge(),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isUnread || isLatestInConversation
                  ? FontWeight.w800
                  : FontWeight.w500,
            ),
          ),
        ),
        if (replyCount > 0) ...[
          const SizedBox(width: 8),
          Text(
            '$replyCount replies',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF5F6368),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class OutboundMessageBadge extends StatelessWidget {
  const OutboundMessageBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFB7D7F8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send_outlined, size: 13, color: Color(0xFF2563A8)),
            const SizedBox(width: 4),
            Text(
              'Sent',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF2563A8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
