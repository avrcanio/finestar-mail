import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/mail_conversation.dart';
import '../../domain/entities/mail_folder.dart';
import '../../domain/entities/mail_message_summary.dart';
import 'conversation_display_helpers.dart';
import 'message_list_tile.dart';

const _threadRailWidth = 40.0;
const _threadRailColor = Color(0xFFB7D7F8);
const _threadRailAccentColor = Color(0xFF2563A8);
const _replyBackgroundColor = Color(0xFFF8FBFF);

class ConversationCard extends StatelessWidget {
  const ConversationCard({
    super.key,
    required this.conversation,
    required this.folder,
    required this.selectedMessageIds,
    required this.selectionActive,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onToggleSelected,
    required this.onShowActions,
  });

  final MailConversation conversation;
  final MailFolder folder;
  final Set<String> selectedMessageIds;
  final bool selectionActive;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final messages = conversationTimelinePreview(conversation);
    final canCollapse = messages.length > 3;
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
        isCollapsed: canCollapse && isCollapsed,
        showCollapseToggle: canCollapse,
        onToggleCollapsed: onToggleCollapsed,
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
    required this.isCollapsed,
    required this.showCollapseToggle,
    required this.onToggleCollapsed,
    required this.folder,
    required this.selectedMessageIds,
    required this.selectionActive,
    required this.onToggleSelected,
    required this.onShowActions,
  });

  final MailConversation conversation;
  final List<MailConversationMessage> messages;
  final bool isCollapsed;
  final bool showCollapseToggle;
  final VoidCallback onToggleCollapsed;
  final MailFolder folder;
  final Set<String> selectedMessageIds;
  final bool selectionActive;
  final ValueChanged<String> onToggleSelected;
  final MessageActionCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems(messages, isCollapsed);

    return Column(
      children: [
        for (var index = 0; index < visibleItems.length; index++) ...[
          if (index == 1 && showCollapseToggle)
            ConversationCollapseToggle(
              key: ValueKey('conversation-collapse-toggle-${conversation.id}'),
              isCollapsed: isCollapsed,
              hiddenMessageCount: _hiddenMessageCount(messages, isCollapsed),
              onPressed: onToggleCollapsed,
            ),
          ConversationTimelineItem(
            conversation: conversation,
            item: visibleItems[index],
            folder: folder,
            selected: selectedMessageIds.contains(
              visibleItems[index].message.id,
            ),
            selectionActive: selectionActive,
            onToggleSelected: onToggleSelected,
            onShowActions: onShowActions,
            isRoot: identical(visibleItems[index], messages.first),
            isLast: index == visibleItems.length - 1,
            isLatestInConversation:
                visibleItems[index].message.id == messages.last.message.id,
          ),
        ],
        if (showCollapseToggle && visibleItems.length <= 1)
          ConversationCollapseToggle(
            key: ValueKey('conversation-collapse-toggle-${conversation.id}'),
            isCollapsed: isCollapsed,
            hiddenMessageCount: _hiddenMessageCount(messages, isCollapsed),
            onPressed: onToggleCollapsed,
          ),
      ],
    );
  }

  List<MailConversationMessage> _visibleItems(
    List<MailConversationMessage> messages,
    bool isCollapsed,
  ) {
    if (!isCollapsed || messages.length <= 3) {
      return messages;
    }
    if (messages.first.message.id == messages.last.message.id) {
      return [messages.first];
    }
    return [messages.first, messages.last];
  }

  int _hiddenMessageCount(
    List<MailConversationMessage> messages,
    bool isCollapsed,
  ) {
    if (!isCollapsed || messages.length <= 3) {
      return 0;
    }
    final visibleCount = messages.first.message.id == messages.last.message.id
        ? 1
        : 2;
    return (messages.length - visibleCount).clamp(0, messages.length);
  }
}

class ConversationCollapseToggle extends StatelessWidget {
  const ConversationCollapseToggle({
    super.key,
    required this.isCollapsed,
    required this.hiddenMessageCount,
    required this.onPressed,
  });

  final bool isCollapsed;
  final int hiddenMessageCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isCollapsed ? 'Show $hiddenMessageCount more' : 'Show less';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            width: _threadRailWidth,
            height: 40,
            child: _ThreadRailSegment(showDot: true, isLast: false),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPressed,
                style: TextButton.styleFrom(
                  foregroundColor: _threadRailAccentColor,
                  backgroundColor: const Color(0xFFEAF4FF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: _threadRailColor),
                  ),
                ),
                icon: Icon(
                  isCollapsed ? Icons.expand_more : Icons.expand_less,
                  size: 18,
                ),
                label: Text(label),
              ),
            ),
          ),
        ],
      ),
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
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: tile);
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
          width: _threadRailWidth,
          height: isLast ? 74 : 96,
          child: _ThreadRailSegment(showDot: true, isLast: isLast),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 2, bottom: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _replyBackgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE5EEF8)),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThreadRailSegment extends StatelessWidget {
  const _ThreadRailSegment({required this.showDot, required this.isLast});

  final bool showDot;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          top: 0,
          bottom: isLast ? 28 : 0,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: _threadRailColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (showDot)
          Positioned(
            top: 18,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _threadRailAccentColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
