import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_route.dart';
import '../../../core/widgets/state_views.dart';
import '../../compose/domain/entities/reply_context.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_message_attachment.dart';
import '../domain/entities/mail_thread.dart';
import 'mailbox_controller.dart';

const _screenBackground = Color(0xFFF7F8FC);
const _mutedText = Color(0xFF5D636B);

class MessageDetailScreen extends ConsumerStatefulWidget {
  const MessageDetailScreen({
    super.key,
    required this.messageId,
    this.emailHtmlViewBuilder,
  });

  final String messageId;
  final Widget Function(String html)? emailHtmlViewBuilder;

  @override
  ConsumerState<MessageDetailScreen> createState() =>
      _MessageDetailScreenState();
}

class _MessageDetailScreenState extends ConsumerState<MessageDetailScreen> {
  final _expandedMessageIds = <String>{};
  final _visibleQuotedMessageIds = <String>{};
  final _markedReadMessageIds = <String>{};
  final _downloadingAttachmentIds = <String>{};
  String? _initializedThreadMessageId;
  bool _isProcessingMessage = false;

  @override
  Widget build(BuildContext context) {
    final threadAsync = ref.watch(messageThreadProvider(widget.messageId));

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: threadAsync.when(
                data: (thread) {
                  _ensureDefaultExpansion(thread);
                  _markSelectedMessageRead(thread);
                  return Column(
                    children: [
                      _MessageTopBar(
                        isProcessing: _isProcessingMessage,
                        mode: _selectedMessageIsTrash(thread)
                            ? _MessageTopBarMode.restore
                            : _MessageTopBarMode.delete,
                        onBack: _navigateBack,
                        onAction: () => _selectedMessageIsTrash(thread)
                            ? _restoreSelectedMessageToInbox(thread)
                            : _moveSelectedMessageToTrash(thread),
                      ),
                      Expanded(
                        child: _MessageThreadContent(
                          thread: thread,
                          expandedMessageIds: _expandedMessageIds,
                          visibleQuotedMessageIds: _visibleQuotedMessageIds,
                          emailHtmlViewBuilder: widget.emailHtmlViewBuilder,
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
                          downloadingAttachmentIds: _downloadingAttachmentIds,
                          onDownloadAttachment: _downloadAttachment,
                        ),
                      ),
                    ],
                  );
                },
                error: (error, stackTrace) => Column(
                  children: [
                    _MessageTopBar(
                      isProcessing: false,
                      mode: _MessageTopBarMode.disabled,
                      onBack: _navigateBack,
                      onAction: () {},
                    ),
                    Expanded(child: ErrorStateView(message: error.toString())),
                  ],
                ),
                loading: () => Column(
                  children: [
                    _MessageTopBar(
                      isProcessing: false,
                      mode: _MessageTopBarMode.disabled,
                      onBack: _navigateBack,
                      onAction: () {},
                    ),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoute.inbox.path);
    }
  }

  Future<void> _moveSelectedMessageToTrash(MailThread thread) async {
    if (_isProcessingMessage || _selectedMessageIsTrash(thread)) {
      return;
    }
    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return;
    }

    setState(() => _isProcessingMessage = true);
    try {
      final result = await ref
          .read(mailboxRepositoryProvider)
          .moveMessageToTrash(
            accountId: account.id,
            messageId: thread.selectedMessageId,
          );
      if (!mounted) {
        return;
      }
      if (result.movedAny) {
        ref.invalidate(mailboxMessagesControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved message to Trash.')),
        );
        _navigateBack();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.failed.isEmpty
                  ? 'Move to Trash failed.'
                  : result.failed.first.message,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingMessage = false);
      }
    }
  }

  Future<void> _restoreSelectedMessageToInbox(MailThread thread) async {
    if (_isProcessingMessage || !_selectedMessageIsTrash(thread)) {
      return;
    }
    final account = await ref.read(activeAccountProvider.future);
    if (account == null) {
      return;
    }

    setState(() => _isProcessingMessage = true);
    try {
      final result = await ref
          .read(mailboxRepositoryProvider)
          .restoreMessageToInbox(
            accountId: account.id,
            messageId: thread.selectedMessageId,
          );
      if (!mounted) {
        return;
      }
      if (result.restoredAny) {
        ref.invalidate(mailboxMessagesControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restored message to INBOX.')),
        );
        _navigateBack();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.failed.isEmpty
                  ? 'Restore to INBOX failed.'
                  : result.failed.first.message,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingMessage = false);
      }
    }
  }

  bool _selectedMessageIsTrash(MailThread thread) {
    MailThreadMessage? selected;
    for (final message in thread.messages) {
      if (message.id == thread.selectedMessageId) {
        selected = message;
        break;
      }
    }
    final folderName = selected?.folderName.trim().toLowerCase() ?? '';
    return folderName == 'trash' ||
        folderName == 'inbox.trash' ||
        folderName == 'deleted items' ||
        folderName == 'deleted messages';
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

  void _markSelectedMessageRead(MailThread thread) {
    final messageId = thread.selectedMessageId;
    if (!_markedReadMessageIds.add(messageId)) {
      return;
    }

    Future.microtask(() async {
      final account = await ref.read(activeAccountProvider.future);
      if (account == null) {
        return;
      }
      await ref
          .read(mailboxRepositoryProvider)
          .setMessageRead(
            accountId: account.id,
            messageId: messageId,
            isRead: true,
          );
      if (mounted) {
        ref.invalidate(mailboxMessagesControllerProvider);
      }
    });
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

  Future<void> _downloadAttachment(
    MailThreadMessage message,
    MailMessageAttachment attachment,
  ) async {
    final downloadKey = '${message.id}:${attachment.id}';
    if (!_downloadingAttachmentIds.add(downloadKey)) {
      return;
    }
    setState(() {});
    try {
      final account = await ref.read(activeAccountProvider.future);
      if (account == null) {
        _showSnackBar('Active account session is missing.');
        return;
      }
      final downloaded = await ref
          .read(mailboxRepositoryProvider)
          .downloadAttachment(
            accountId: account.id,
            messageId: message.id,
            attachment: attachment,
          );
      final file = await _saveAttachment(downloaded);
      final openResult = await OpenFilex.open(
        file.path,
        type: downloaded.contentType,
      );
      if (openResult.type != ResultType.done) {
        _showSnackBar(openResult.message);
      }
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      _downloadingAttachmentIds.remove(downloadKey);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<File> _saveAttachment(DownloadedMailAttachment attachment) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = await Directory(
      p.join(root.path, 'attachments'),
    ).create(recursive: true);
    final file = File(
      p.join(directory.path, _safeFilename(attachment.filename)),
    );
    return file.writeAsBytes(attachment.bytes, flush: true);
  }

  String _safeFilename(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return 'attachment.bin';
    }
    return sanitized;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _MessageTopBarMode { delete, restore, disabled }

class _MessageTopBar extends StatelessWidget {
  const _MessageTopBar({
    required this.onBack,
    required this.onAction,
    required this.mode,
    required this.isProcessing,
  });

  final VoidCallback onBack;
  final VoidCallback onAction;
  final _MessageTopBarMode mode;
  final bool isProcessing;

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
            tooltip: mode == _MessageTopBarMode.restore
                ? 'Restore to INBOX'
                : 'Delete',
            onPressed: mode != _MessageTopBarMode.disabled && !isProcessing
                ? onAction
                : null,
            icon: isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Icon(
                    mode == _MessageTopBarMode.restore
                        ? Icons.restore_from_trash_outlined
                        : Icons.delete_outline,
                  ),
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
    required this.emailHtmlViewBuilder,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
    required this.downloadingAttachmentIds,
    required this.onDownloadAttachment,
  });

  final MailThread thread;
  final Set<String> expandedMessageIds;
  final Set<String> visibleQuotedMessageIds;
  final Widget Function(String html)? emailHtmlViewBuilder;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<String> onToggleQuoted;
  final ValueChanged<MailThreadMessage> onReply;
  final ValueChanged<MailThreadMessage> onForward;
  final Set<String> downloadingAttachmentIds;
  final void Function(MailThreadMessage, MailMessageAttachment)
  onDownloadAttachment;

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
            emailHtmlViewBuilder: emailHtmlViewBuilder,
            onReply: () => onReply(message),
            onForward: () => onForward(message),
            downloadingAttachmentIds: downloadingAttachmentIds,
            onDownloadAttachment: onDownloadAttachment,
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
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.06,
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
    required this.emailHtmlViewBuilder,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
    required this.downloadingAttachmentIds,
    required this.onDownloadAttachment,
  });

  final MailThreadMessage message;
  final bool isExpanded;
  final bool isQuotedVisible;
  final Widget Function(String html)? emailHtmlViewBuilder;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleQuoted;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final Set<String> downloadingAttachmentIds;
  final void Function(MailThreadMessage, MailMessageAttachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    final quotedBody = message.quotedBody;
    final body = message.visibleBody.isEmpty
        ? message.bodyPlain
        : message.visibleBody;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
            _MessageBodyView(
              body: body,
              htmlBody: message.bodyHtml,
              isExpanded: isExpanded,
              onToggleExpanded: onToggleExpanded,
              emailHtmlViewBuilder: emailHtmlViewBuilder,
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
            if (isExpanded && _visibleAttachmentChips(message).isNotEmpty) ...[
              const SizedBox(height: 16),
              _AttachmentList(
                message: message,
                attachments: _visibleAttachmentChips(message),
                downloadingAttachmentIds: downloadingAttachmentIds,
                onDownloadAttachment: onDownloadAttachment,
              ),
            ],
          ],
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

class _MessageBodyView extends StatelessWidget {
  const _MessageBodyView({
    required this.body,
    required this.htmlBody,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.emailHtmlViewBuilder,
  });

  final String body;
  final String? htmlBody;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final Widget Function(String html)? emailHtmlViewBuilder;

  @override
  Widget build(BuildContext context) {
    final html = htmlBody?.trim();
    if (isExpanded && html != null && html.isNotEmpty) {
      final builder = emailHtmlViewBuilder;
      if (builder != null) {
        return builder(html);
      }
      return _EmailHtmlView(html: html);
    }

    final text = Text(
      body,
      maxLines: isExpanded ? null : 2,
      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF202124),
        fontSize: 16,
        height: 1.42,
        letterSpacing: 0,
      ),
    );
    if (isExpanded) {
      return text;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggleExpanded,
      child: SizedBox(width: double.infinity, child: text),
    );
  }
}

class _EmailHtmlView extends StatefulWidget {
  const _EmailHtmlView({required this.html});

  final String html;

  @override
  State<_EmailHtmlView> createState() => _EmailHtmlViewState();
}

class _EmailHtmlViewState extends State<_EmailHtmlView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) {
              return NavigationDecision.prevent;
            }
            if (_isExternalLink(uri)) {
              unawaited(_openExternalUrl(uri));
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_wrapEmailHtml(widget.html));
  }

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.62)
        .clamp(360.0, 720.0)
        .toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        key: const ValueKey('email-html-webview'),
        height: height,
        width: double.infinity,
        child: WebViewWidget(
          controller: _controller,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
        ),
      ),
    );
  }
}

bool _isExternalLink(Uri uri) {
  return uri.scheme == 'http' ||
      uri.scheme == 'https' ||
      uri.scheme == 'mailto' ||
      uri.scheme == 'tel';
}

Future<void> _openExternalUrl(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Ignore failed external handoff; the email view must never navigate inline.
  }
}

String _wrapEmailHtml(String rawHtml) {
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: #ffffff;
      color: #222222;
    }
    body {
      overflow-wrap: break-word;
      -webkit-text-size-adjust: 100%;
    }
    img, table {
      max-width: 100%;
    }
  </style>
</head>
<body>
$rawHtml
</body>
</html>
''';
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({
    required this.message,
    required this.attachments,
    required this.downloadingAttachmentIds,
    required this.onDownloadAttachment,
  });

  final MailThreadMessage message;
  final List<MailMessageAttachment> attachments;
  final Set<String> downloadingAttachmentIds;
  final void Function(MailThreadMessage, MailMessageAttachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in attachments)
          _AttachmentChip(
            attachment: attachment,
            isDownloading: downloadingAttachmentIds.contains(
              '${message.id}:${attachment.id}',
            ),
            onTap: () => onDownloadAttachment(message, attachment),
          ),
      ],
    );
  }
}

List<MailMessageAttachment> _visibleAttachmentChips(MailThreadMessage message) {
  return message.attachments
      .where(
        (attachment) =>
            !_isReferencedInlineCidResource(message.bodyHtml, attachment),
      )
      .toList();
}

bool _isReferencedInlineCidResource(
  String? html,
  MailMessageAttachment attachment,
) {
  if (!attachment.isInline || html == null || html.isEmpty) {
    return false;
  }
  final contentId = attachment.contentId.trim();
  if (contentId.isEmpty) {
    return false;
  }
  return _cidReferencePattern(contentId).hasMatch(html);
}

RegExp _cidReferencePattern(String contentId) {
  final normalized = contentId.trim();
  final candidates = {
    normalized,
    '<$normalized>',
    Uri.encodeComponent(normalized),
    Uri.encodeComponent('<$normalized>'),
  }.where((candidate) => candidate.isNotEmpty).map(RegExp.escape).join('|');
  return RegExp('cid:\\s*(?:$candidates)', caseSensitive: false);
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.isDownloading,
    required this.onTap,
  });

  final MailMessageAttachment attachment;
  final bool isDownloading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ActionChip(
      avatar: isDownloading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(Icons.attach_file, size: 18, color: primary),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              attachment.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: primary, fontWeight: FontWeight.w600),
            ),
            Text(
              _attachmentSubtitle(attachment),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _mutedText,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
      onPressed: isDownloading ? null : onTap,
      backgroundColor: const Color(0xFFEAF3FF),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }
}

String _attachmentSubtitle(MailMessageAttachment attachment) {
  final size = attachment.sizeBytes == null
      ? null
      : _formatBytes(attachment.sizeBytes!);
  final type = attachment.contentType.trim();
  if (size == null) {
    return type.isEmpty ? 'Attachment' : type;
  }
  return type.isEmpty ? size : '$type - $size';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
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
