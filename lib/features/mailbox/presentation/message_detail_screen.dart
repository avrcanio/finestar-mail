import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_route.dart';
import '../../../core/widgets/state_views.dart';
import '../../compose/domain/entities/reply_context.dart';
import '../domain/entities/mail_thread.dart';
import 'mailbox_controller.dart';

const _screenBackground = Color(0xFFF7F8FC);
const _mutedText = Color(0xFF5D636B);

class MessageDetailScreen extends ConsumerStatefulWidget {
  const MessageDetailScreen({super.key, required this.messageId});

  final String messageId;

  @override
  ConsumerState<MessageDetailScreen> createState() =>
      _MessageDetailScreenState();
}

class _MessageDetailScreenState extends ConsumerState<MessageDetailScreen> {
  final _expandedMessageIds = <String>{};
  final _visibleQuotedMessageIds = <String>{};
  String? _initializedThreadMessageId;

  @override
  Widget build(BuildContext context) {
    final threadAsync = ref.watch(messageThreadProvider(widget.messageId));

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
              child: threadAsync.when(
                data: (thread) {
                  _ensureDefaultExpansion(thread);
                  return _MessageThreadContent(
                    thread: thread,
                    expandedMessageIds: _expandedMessageIds,
                    visibleQuotedMessageIds: _visibleQuotedMessageIds,
                    onToggleExpanded: _toggleExpanded,
                    onToggleQuoted: _toggleQuoted,
                    onReply: (message) => _openCompose(
                      context: context,
                      thread: thread,
                      message: message,
                      action: ReplyAction.reply,
                    ),
                    onForward: (message) => _openCompose(
                      context: context,
                      thread: thread,
                      message: message,
                      action: ReplyAction.forward,
                    ),
                  );
                },
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

  void _ensureDefaultExpansion(MailThread thread) {
    if (_initializedThreadMessageId == thread.selectedMessageId) {
      return;
    }

    _initializedThreadMessageId = thread.selectedMessageId;
    _expandedMessageIds
      ..clear()
      ..add(thread.selectedMessageId);
    if (thread.messages.isNotEmpty) {
      _expandedMessageIds.add(thread.messages.last.id);
    }
    _visibleQuotedMessageIds.clear();
  }

  void _toggleExpanded(String messageId) {
    setState(() {
      if (!_expandedMessageIds.add(messageId)) {
        _expandedMessageIds.remove(messageId);
      }
    });
  }

  void _toggleQuoted(String messageId) {
    setState(() {
      if (!_visibleQuotedMessageIds.add(messageId)) {
        _visibleQuotedMessageIds.remove(messageId);
      }
    });
  }

  void _openCompose({
    required BuildContext context,
    required MailThread thread,
    required MailThreadMessage message,
    required ReplyAction action,
  }) {
    context.push(
      AppRoute.compose.path,
      extra: ReplyContext(
        messageId: thread.selectedMessageId,
        targetMessageId: message.id,
        subject: thread.subject,
        action: action,
        recipients: switch (action) {
          ReplyAction.reply || ReplyAction.replyAll => [message.sender],
          ReplyAction.forward => const [],
        },
        originalSender: message.sender,
        originalReceivedAt: message.receivedAt,
        originalBody: message.visibleBody,
        originalMessageIdHeader: message.messageIdHeader,
        originalReferencesHeader: message.referencesHeader,
      ),
    );
  }
}

class _MessageTopBar extends StatelessWidget {
  const _MessageTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Color(0xFF202124)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Archive',
            onPressed: () {},
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () {},
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Mark unread',
            onPressed: () {},
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
          IconButton(
            tooltip: 'More options',
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }
}

class _MessageThreadContent extends StatelessWidget {
  const _MessageThreadContent({
    required this.thread,
    required this.expandedMessageIds,
    required this.visibleQuotedMessageIds,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
  });

  final MailThread thread;
  final Set<String> expandedMessageIds;
  final Set<String> visibleQuotedMessageIds;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<String> onToggleQuoted;
  final ValueChanged<MailThreadMessage> onReply;
  final ValueChanged<MailThreadMessage> onForward;

  @override
  Widget build(BuildContext context) {
    final selectedFolder = _selectedFolderName(thread);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
      children: [
        _SubjectHeader(subject: thread.subject, folderName: selectedFolder),
        const SizedBox(height: 18),
        for (final message in thread.messages) ...[
          _ThreadMessageCard(
            message: message,
            isExpanded: expandedMessageIds.contains(message.id),
            isQuotedVisible: visibleQuotedMessageIds.contains(message.id),
            onToggleExpanded: () => onToggleExpanded(message.id),
            onToggleQuoted: () => onToggleQuoted(message.id),
            onReply: () => onReply(message),
            onForward: () => onForward(message),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String? _selectedFolderName(MailThread thread) {
    for (final message in thread.messages) {
      if (message.id == thread.selectedMessageId) {
        return message.folderName;
      }
    }
    return null;
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({required this.subject, required this.folderName});

  final String subject;
  final String? folderName;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                subject,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF202124),
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                  letterSpacing: 0,
                ),
              ),
              if (folderName != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(folderName!),
                  backgroundColor: const Color(0xFFFFD08A),
                  side: BorderSide.none,
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF5B3B00),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Star',
          onPressed: () {},
          icon: const Icon(Icons.star_border, color: _mutedText),
        ),
      ],
    );
  }
}

class _ThreadMessageCard extends StatelessWidget {
  const _ThreadMessageCard({
    required this.message,
    required this.isExpanded,
    required this.isQuotedVisible,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
  });

  final MailThreadMessage message;
  final bool isExpanded;
  final bool isQuotedVisible;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleQuoted;
  final VoidCallback onReply;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final quotedBody = message.quotedBody;
    final body = message.visibleBody.isEmpty
        ? message.bodyPlain
        : message.visibleBody;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggleExpanded,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SenderAvatar(sender: message.sender),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _senderLabel(message.sender),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF202124),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                            Text(
                              DateFormat('h:mm a').format(message.receivedAt),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: _mutedText,
                                    fontSize: 14,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'to ${message.recipients.join(', ')} · ${message.folderName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _mutedText,
                                fontSize: 15,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reply',
                    onPressed: onReply,
                    icon: const Icon(Icons.reply, color: _mutedText),
                  ),
                  IconButton(
                    tooltip: 'Forward',
                    onPressed: onForward,
                    icon: const Icon(Icons.forward, color: _mutedText),
                  ),
                  IconButton(
                    tooltip: 'Message options',
                    onPressed: () {},
                    icon: const Icon(Icons.more_vert, color: _mutedText),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                body,
                maxLines: isExpanded ? null : 2,
                overflow: isExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF202124),
                  fontSize: 16,
                  height: 1.42,
                  letterSpacing: 0,
                ),
              ),
              if (isExpanded && quotedBody != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onToggleQuoted,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text(
                    isQuotedVisible ? 'Hide quoted text' : 'Show quoted text',
                  ),
                ),
                if (isQuotedVisible) ...[
                  const SizedBox(height: 8),
                  Text(
                    quotedBody,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF202124),
                      fontSize: 16,
                      height: 1.42,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _senderLabel(String sender) {
    final localPart = sender.split('@').first.trim();
    if (localPart.isEmpty) {
      return sender;
    }
    return localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part.characters.first.toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.sender});

  final String sender;

  @override
  Widget build(BuildContext context) {
    final initial = sender.trim().isEmpty
        ? '?'
        : sender.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFF47C4D6),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
