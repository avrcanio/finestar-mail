import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/mail_conversation.dart';
import '../../domain/entities/mail_folder.dart';
import '../../domain/entities/mail_message_summary.dart';
import 'conversation_display_helpers.dart';
import 'message_list_tile.dart';

class ConversationCard extends StatelessWidget {
  const ConversationCard({
    super.key,
    required this.conversation,
    required this.folder,
    required this.selectedMessageIds,
    required this.selectionActive,
    required this.onToggleSelected,
    required this.onShowActions,
  });

  final MailConversation conversation;
  final MailFolder folder;
  final Set<String> selectedMessageIds;
  final bool selectionActive;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final messages = conversationTimelinePreview(conversation);
    return SectionCard(
      color:
          messages.any(
            (message) => selectedMessageIds.contains(message.message.id),
          )
          ? const Color(0xFFD7EAFE)
          : conversation.hasUnread
          ? const Color(0xFFEAF4FF)
          : Colors.white,
      padding: const EdgeInsets.all(0),
      child: ConversationTimeline(
        conversation: conversation,
        messages: messages,
        folder: folder,
        selectedMessageIds: selectedMessageIds,
        selectionActive: selectionActive,
        onToggleSelected: onToggleSelected,
        onShowActions: onShowActions,
      ),
    );
  }
}

class ConversationTimeline extends StatelessWidget {
  const ConversationTimeline({
    super.key,
    required this.conversation,
    required this.messages,
    required this.folder,
    required this.selectedMessageIds,
    required this.selectionActive,
    required this.onToggleSelected,
    required this.onShowActions,
  });

  final MailConversation conversation;
  final List<MailConversationMessage> messages;
  final MailFolder folder;
  final Set<String> selectedMessageIds;
  final bool selectionActive;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < messages.length; index++)
          ConversationTimelineItem(
            conversation: conversation,
            item: messages[index],
            folder: folder,
            selected: selectedMessageIds.contains(messages[index].message.id),
            selectionActive: selectionActive,
            onToggleSelected: onToggleSelected,
            onShowActions: onShowActions,
            isRoot: index == 0,
            isLast: index == messages.length - 1,
            isLatestInConversation: index == messages.length - 1,
          ),
      ],
    );
  }
}

class ConversationTimelineItem extends StatelessWidget {
  const ConversationTimelineItem({
    super.key,
    required this.conversation,
    required this.item,
    required this.folder,
    required this.selected,
    required this.selectionActive,
    required this.onToggleSelected,
    required this.onShowActions,
    required this.isRoot,
    required this.isLast,
    required this.isLatestInConversation,
  });

  final MailConversation conversation;
  final MailConversationMessage item;
  final MailFolder folder;
  final bool selected;
  final bool selectionActive;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;
  final bool isRoot;
  final bool isLast;
  final bool isLatestInConversation;

  @override
  Widget build(BuildContext context) {
    final message = item.message;
    final tile = MailMessageListTile(
      message: message,
      folder: folder,
      selected: selected,
      selectionEnabled: true,
      selectionActive: selectionActive,
      onToggleSelected: onToggleSelected,
      onShowActions: onShowActions,
      hasAttachments: isRoot ? conversation.hasVisibleAttachments : null,
      isUnread: isRoot ? conversation.hasUnread : null,
      isImportant: isRoot ? message.isImportant : null,
      isPinned: isRoot ? message.isPinned : null,
      replyCount: isRoot ? conversation.replyCount : 0,
      direction: item.direction,
      displaySubject: displayConversationSubject(message.subject),
      showOutboundBadge: true,
      isLatestInConversation: isLatestInConversation,
      title: isRoot
          ? ConversationHeader(
              conversation: conversation,
              message: message,
              direction: item.direction,
              isLatestInConversation: isLatestInConversation,
            )
          : null,
    );

    if (isRoot) {
      return tile;
    }

    return _ThreadReplyRow(isLast: isLast, child: tile);
  }
}

class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.conversation,
    required this.message,
    required this.direction,
    required this.isLatestInConversation,
  });

  final MailConversation conversation;
  final MailMessageSummary message;
  final MailConversationDirection direction;
  final bool isLatestInConversation;

  @override
  Widget build(BuildContext context) {
    final isOutbound = direction == MailConversationDirection.outbound;

    return Row(
      children: [
        if (isOutbound) ...[
          const OutboundMessageBadge(),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            displayConversationSubject(message.subject),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: conversation.hasUnread || isLatestInConversation
                  ? FontWeight.w800
                  : FontWeight.w500,
            ),
          ),
        ),
        if (conversation.replyCount > 0) ...[
          const SizedBox(width: 8),
          Text(
            '${conversation.replyCount} replies',
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

class _ThreadReplyRow extends StatelessWidget {
  const _ThreadReplyRow({required this.isLast, required this.child});

  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 2,
              height: isLast ? 58 : 92,
              color: const Color(0xFFDADCE0),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
