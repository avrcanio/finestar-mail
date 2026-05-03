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
import '../../../core/constants/mail_translation_languages.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../compose/domain/entities/reply_context.dart';
import '../domain/entities/mail_message_attachment.dart';
import '../domain/entities/mail_message_translation.dart';
import '../domain/entities/mail_thread.dart';
import 'mailbox_controller.dart';
import 'message_detail_route_result.dart';
import 'message_translation_controller.dart';
import 'pdf_attachment_viewer_screen.dart';

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
  final _outerScrollController = ScrollController();
  final _expandedMessageIds = <String>{};
  final _visibleQuotedMessageIds = <String>{};
  final _markedReadMessageIds = <String>{};
  final _downloadingAttachmentIds = <String>{};
  final _locallyRemovedMessageIds = <String>{};
  final _deletedMessageIdsForRoute = <String>{};
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
                  final visibleThread =
                      MailboxDeleteStateRemoval.removeFromThread(
                        thread,
                        _locallyRemovedMessageIds,
                      );
                  if (visibleThread == null) {
                    return Column(
                      children: [
                        _MessageTopBar(
                          isProcessing: _isProcessingMessage,
                          mode: _MessageTopBarMode.disabled,
                          onBack: _navigateBack,
                          onAction: () {},
                          onTranslate: null,
                          onToggleTranslation: null,
                          isTranslating: false,
                          hasTranslation: false,
                          showTranslated: false,
                        ),
                        const Expanded(
                          child: EmptyStateView(
                            title: 'No messages to show',
                            message: 'This conversation has no visible mail.',
                          ),
                        ),
                      ],
                    );
                  }
                  _ensureDefaultExpansion(visibleThread);
                  _markSelectedMessageRead(visibleThread);
                  final selectedMessageId = visibleThread.selectedMessageId;
                  final translationAsync = ref.watch(
                    messageTranslationControllerProvider(selectedMessageId),
                  );
                  final translationState = translationAsync.asData?.value;
                  final translation = translationState?.translation;
                  final showTranslated =
                      translationState?.showTranslated ?? false;
                  final translatedSubject =
                      translation?.translatedSubject.trim() ?? '';
                  final translatedBody =
                      translation?.translatedText.trim() ?? '';
                  final translatedHtml =
                      translation?.translatedHtml.trim() ?? '';
                  final hasAnyTranslatedContent =
                      translatedSubject.isNotEmpty ||
                      translatedBody.isNotEmpty ||
                      translatedHtml.isNotEmpty;
                  final displaySubject =
                      showTranslated && translatedSubject.isNotEmpty
                          ? translatedSubject
                          : visibleThread.subject;
                  return Column(
                    children: [
                      _MessageTopBar(
                        isProcessing: _isProcessingMessage,
                        mode: _selectedMessageIsTrash(visibleThread)
                            ? _MessageTopBarMode.restore
                            : _MessageTopBarMode.delete,
                        onBack: _navigateBack,
                        onAction: () => _selectedMessageIsTrash(visibleThread)
                            ? _restoreSelectedMessageToInbox(visibleThread)
                            : _moveSelectedMessageToTrash(visibleThread),
                        onTranslate: _selectedMessageIsTrash(visibleThread)
                            ? null
                            : () => _translateSelectedMessage(visibleThread),
                        onToggleTranslation:
                            translation == null || !hasAnyTranslatedContent
                                ? null
                                : () => ref
                                    .read(
                                      messageTranslationControllerProvider(
                                        selectedMessageId,
                                      ).notifier,
                                    )
                                    .toggleShowTranslated(),
                        isTranslating: translationAsync.isLoading,
                        hasTranslation: translation != null,
                        showTranslated: showTranslated,
                      ),
                      if (translationAsync.hasError)
                        _TranslationErrorBanner(
                          message: translationAsync.error.toString(),
                          onRetry: () => ref
                              .read(
                                messageTranslationControllerProvider(
                                  selectedMessageId,
                                ).notifier,
                              )
                              .translate(),
                        ),
                      Expanded(
                        child: _MessageThreadContent(
                          thread: visibleThread,
                          subjectOverride: displaySubject,
                          translation: translation,
                          showTranslated: showTranslated,
                          outerScrollController: _outerScrollController,
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
                            thread: visibleThread,
                            message: message,
                            action: ReplyAction.forward,
                          ),
                          onDeleteMessage: (message) =>
                              _moveMessageToTrash(visibleThread, message.id),
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
                      onTranslate: null,
                      onToggleTranslation: null,
                      isTranslating: false,
                      hasTranslation: false,
                      showTranslated: false,
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
                      onTranslate: null,
                      onToggleTranslation: null,
                      isTranslating: false,
                      hasTranslation: false,
                      showTranslated: false,
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

  @override
  void dispose() {
    _outerScrollController.dispose();
    super.dispose();
  }

  void _navigateBack() {
    if (context.canPop()) {
      context.pop(
        _deletedMessageIdsForRoute.isEmpty
            ? null
            : MessageDetailRouteResult.deleted(
                Set.unmodifiable(_deletedMessageIdsForRoute),
              ),
      );
    } else {
      context.go(AppRoute.inbox.path);
    }
  }

  Future<void> _moveSelectedMessageToTrash(MailThread thread) async {
    await _moveMessageToTrash(thread, thread.selectedMessageId);
  }

  Future<void> _moveMessageToTrash(MailThread thread, String messageId) async {
    if (_isProcessingMessage || _messageIsTrash(thread, messageId)) {
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
          .moveMessageToTrash(accountId: account.id, messageId: messageId);
      if (!mounted) {
        return;
      }
      if (result.movedAny) {
        final movedIds = result.movedMessageIds.toSet();
        final remainingThread = MailboxDeleteStateRemoval.removeFromThread(
          thread,
          movedIds,
        );
        setState(() {
          _locallyRemovedMessageIds.addAll(movedIds);
          _deletedMessageIdsForRoute.addAll(movedIds);
          _expandedMessageIds.removeAll(movedIds);
          _visibleQuotedMessageIds.removeAll(movedIds);
        });
        ref.invalidate(mailboxMessagesControllerProvider);
        ref.invalidate(mailboxConversationsControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved message to Trash.')),
        );
        if (remainingThread == null) {
          _navigateBack();
        }
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
    return _messageIsTrash(thread, thread.selectedMessageId);
  }

  bool _messageIsTrash(MailThread thread, String messageId) {
    MailThreadMessage? selected;
    for (final message in thread.messages) {
      if (message.id == messageId) {
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
    final visibleAttachments = action == ReplyAction.forward
        ? _visibleAttachmentChips(message)
        : const <MailMessageAttachment>[];
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
        forwardSourceFolder: action == ReplyAction.forward
            ? message.folderPath
            : null,
        forwardSourceUid: action == ReplyAction.forward
            ? message.backendUid
            : null,
        forwardedAttachments: [
          for (final attachment in visibleAttachments)
            ForwardedAttachmentRef(
              attachmentId: attachment.id,
              fileName: attachment.filename,
              sizeBytes: attachment.sizeBytes,
              mimeType: attachment.contentType,
            ),
        ],
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
      if (_isPdfAttachment(downloaded, attachment) && !kIsWeb) {
        if (!mounted) {
          return;
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => PdfAttachmentViewerScreen(
              file: file,
              title: attachment.filename,
            ),
          ),
        );
      } else {
        final openResult = await OpenFilex.open(
          file.path,
          type: downloaded.contentType,
        );
        if (openResult.type != ResultType.done) {
          _showSnackBar(openResult.message);
        }
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

  bool _isPdfAttachment(
    DownloadedMailAttachment downloaded,
    MailMessageAttachment attachment,
  ) {
    bool looksPdf(String name, String contentType) {
      final lowerName = name.toLowerCase();
      final lowerType = contentType.toLowerCase();
      if (lowerName.endsWith('.pdf')) {
        return true;
      }
      return lowerType.contains('pdf');
    }

    return looksPdf(attachment.filename, attachment.contentType) ||
        looksPdf(downloaded.filename, downloaded.contentType);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _translateSelectedMessage(MailThread thread) async {
    final selectedId = thread.selectedMessageId;
    final asyncState = ref.read(
      messageTranslationControllerProvider(selectedId),
    );
    final currentLanguage = asyncState.asData?.value.targetLanguage ??
        MessageTranslationController.fallbackLanguage;
    final hasExistingTranslation =
        asyncState.asData?.value.translation != null;
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Translate to'),
          children: [
            for (final entry in kMailTranslationLanguageLabels.entries)
              ListTile(
                title: Text('${entry.value} (${entry.key})'),
                trailing: entry.key == currentLanguage
                    ? const Icon(Icons.check, color: _mutedText)
                    : null,
                onTap: () => Navigator.of(dialogContext).pop(entry.key),
              ),
          ],
        );
      },
    );
    if (!mounted || picked == null) {
      return;
    }
    final controller = ref.read(
      messageTranslationControllerProvider(selectedId).notifier,
    );
    try {
      await controller.setTargetLanguage(picked);
      if (hasExistingTranslation && picked.trim() == currentLanguage.trim()) {
        controller.toggleShowTranslated();
        return;
      }
      await controller.translate();
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }
}

class _TranslationErrorBanner extends StatelessWidget {
  const _TranslationErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Material(
        color: const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFB42318)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7A271A),
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MessageTopBarMode { delete, restore, disabled }

class _MessageTopBar extends StatelessWidget {
  const _MessageTopBar({
    required this.onBack,
    required this.onAction,
    required this.mode,
    required this.isProcessing,
    required this.onTranslate,
    required this.onToggleTranslation,
    required this.isTranslating,
    required this.hasTranslation,
    required this.showTranslated,
  });

  final VoidCallback onBack;
  final VoidCallback onAction;
  final _MessageTopBarMode mode;
  final bool isProcessing;
  final VoidCallback? onTranslate;
  final VoidCallback? onToggleTranslation;
  final bool isTranslating;
  final bool hasTranslation;
  final bool showTranslated;

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
            tooltip: 'Translate',
            onPressed: onTranslate,
            icon: isTranslating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.translate_outlined),
          ),
          if (hasTranslation)
            IconButton(
              tooltip: showTranslated ? 'Show original' : 'Show translated',
              onPressed: onToggleTranslation,
              icon: Icon(
                showTranslated ? Icons.subject_outlined : Icons.translate,
              ),
            ),
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
    required this.subjectOverride,
    required this.translation,
    required this.showTranslated,
    required this.outerScrollController,
    required this.expandedMessageIds,
    required this.visibleQuotedMessageIds,
    required this.emailHtmlViewBuilder,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
    required this.onDeleteMessage,
    required this.downloadingAttachmentIds,
    required this.onDownloadAttachment,
  });

  final MailThread thread;
  final String subjectOverride;
  final MailMessageTranslation? translation;
  final bool showTranslated;
  final ScrollController outerScrollController;
  final Set<String> expandedMessageIds;
  final Set<String> visibleQuotedMessageIds;
  final Widget Function(String html)? emailHtmlViewBuilder;
  final ValueChanged<String> onToggleExpanded;
  final ValueChanged<String> onToggleQuoted;
  final ValueChanged<MailThreadMessage> onReply;
  final ValueChanged<MailThreadMessage> onForward;
  final ValueChanged<MailThreadMessage> onDeleteMessage;
  final Set<String> downloadingAttachmentIds;
  final void Function(MailThreadMessage, MailMessageAttachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    final selectedFolder = _selectedFolderName(thread);

    return Scrollbar(
      key: const ValueKey('message-detail-outer-scrollbar'),
      controller: outerScrollController,
      thumbVisibility: true,
      trackVisibility: false,
      thickness: 3,
      radius: const Radius.circular(999),
      child: ListView(
        key: const ValueKey('message-detail-outer-scroll-view'),
        controller: outerScrollController,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          _SubjectHeader(
            subject: subjectOverride,
            folderName: selectedFolder,
            translation: translation,
            showTranslated: showTranslated,
          ),
          const SizedBox(height: 18),
          for (final message in thread.messages) ...[
            _ThreadMessageCard(
              message: message,
              outerScrollController: outerScrollController,
              isExpanded: expandedMessageIds.contains(message.id),
              isQuotedVisible: visibleQuotedMessageIds.contains(message.id),
              overrideHtml:
                  showTranslated &&
                          translation != null &&
                          message.id == thread.selectedMessageId &&
                          translation!.translatedHtml.trim().isNotEmpty
                      ? translation!.translatedHtml
                      : null,
              overrideBody:
                  showTranslated &&
                          translation != null &&
                          message.id == thread.selectedMessageId &&
                                          translation!.translatedText.trim().isNotEmpty
                                      ? translation!.translatedText
                      : null,
              onToggleExpanded: () => onToggleExpanded(message.id),
              onToggleQuoted: () => onToggleQuoted(message.id),
              emailHtmlViewBuilder: emailHtmlViewBuilder,
              onReply: () => onReply(message),
              onForward: () => onForward(message),
              onDeleteMessage: () => onDeleteMessage(message),
              downloadingAttachmentIds: downloadingAttachmentIds,
              onDownloadAttachment: onDownloadAttachment,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
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
  const _SubjectHeader({
    required this.subject,
    required this.folderName,
    required this.translation,
    required this.showTranslated,
  });

  final String subject;
  final String? folderName;
  final MailMessageTranslation? translation;
  final bool showTranslated;

  @override
  Widget build(BuildContext context) {
    final translationValue = translation;
    final meta = translationValue == null
        ? null
        : 'Translated to ${translationValue.targetLanguage}'
            '${translationValue.sourceLanguage.trim().isEmpty ? '' : ' · from ${translationValue.sourceLanguage}'}'
            '${translationValue.cached ? ' · cached' : ''}'
            '${translationValue.truncated ? ' · truncated' : ''}';
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
              if (meta != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(meta),
                  backgroundColor:
                      showTranslated ? const Color(0xFFEAF3FF) : _screenBackground,
                  side: BorderSide.none,
                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _mutedText,
                  ),
                ),
              if (showTranslated &&
                  translationValue != null &&
                  translationValue.truncated)
                Text(
                  'Dio poruke nije preveden zbog duljine.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _mutedText,
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
    required this.outerScrollController,
    required this.isExpanded,
    required this.isQuotedVisible,
    required this.emailHtmlViewBuilder,
    required this.overrideHtml,
    required this.overrideBody,
    required this.onToggleExpanded,
    required this.onToggleQuoted,
    required this.onReply,
    required this.onForward,
    required this.onDeleteMessage,
    required this.downloadingAttachmentIds,
    required this.onDownloadAttachment,
  });

  final MailThreadMessage message;
  final ScrollController outerScrollController;
  final bool isExpanded;
  final bool isQuotedVisible;
  final Widget Function(String html)? emailHtmlViewBuilder;
  final String? overrideHtml;
  final String? overrideBody;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleQuoted;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onDeleteMessage;
  final Set<String> downloadingAttachmentIds;
  final void Function(MailThreadMessage, MailMessageAttachment)
  onDownloadAttachment;

  @override
  Widget build(BuildContext context) {
    final htmlOverride = overrideHtml?.trim();
    final bodyOverride = overrideBody?.trim();
    final quotedBody =
        (bodyOverride != null && bodyOverride.isNotEmpty) ||
                (htmlOverride != null && htmlOverride.isNotEmpty)
            ? null
            : message.quotedBody;
    final body =
        (bodyOverride != null && bodyOverride.isNotEmpty)
            ? bodyOverride
            : (message.visibleBody.isEmpty ? message.bodyPlain : message.visibleBody);
    final htmlBody =
        (htmlOverride != null && htmlOverride.isNotEmpty)
            ? htmlOverride
            : ((bodyOverride != null && bodyOverride.isNotEmpty)
                  ? null
                  : message.bodyHtml);

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
                  onPressed: () =>
                      _showThreadMessageMenu(context, onDeleteMessage),
                  icon: const Icon(Icons.more_vert, color: _mutedText),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _MessageBodyView(
              body: body,
              htmlBody: htmlBody,
              isExpanded: isExpanded,
              outerScrollController: outerScrollController,
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

  Future<void> _showThreadMessageMenu(
    BuildContext context,
    VoidCallback onDeleteMessage,
  ) async {
    final action = await showModalBottomSheet<_ThreadMessageAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ComingSoonActionTile(icon: Icons.reply, label: 'Reply'),
                _ComingSoonActionTile(icon: Icons.forward, label: 'Forward'),
                _ComingSoonActionTile(
                  icon: Icons.archive_outlined,
                  label: 'Archive',
                ),
                _ComingSoonActionTile(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Mark unread',
                ),
                _ComingSoonActionTile(
                  icon: Icons.drive_file_move_outlined,
                  label: 'Move',
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Move to Trash'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_ThreadMessageAction.delete),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == _ThreadMessageAction.delete) {
      onDeleteMessage();
    }
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

enum _ThreadMessageAction { delete }

class _ComingSoonActionTile extends StatelessWidget {
  const _ComingSoonActionTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text('$label (Coming soon)'),
    );
  }
}

class _MessageBodyView extends StatelessWidget {
  const _MessageBodyView({
    required this.body,
    required this.htmlBody,
    required this.isExpanded,
    required this.outerScrollController,
    required this.onToggleExpanded,
    required this.emailHtmlViewBuilder,
  });

  final String body;
  final String? htmlBody;
  final bool isExpanded;
  final ScrollController outerScrollController;
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
      return _LinkedPlainBodyScrollView(
        outerScrollController: outerScrollController,
        child: text,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggleExpanded,
      child: SizedBox(width: double.infinity, child: text),
    );
  }
}

class _LinkedPlainBodyScrollView extends StatefulWidget {
  const _LinkedPlainBodyScrollView({
    required this.outerScrollController,
    required this.child,
  });

  final ScrollController outerScrollController;
  final Widget child;

  @override
  State<_LinkedPlainBodyScrollView> createState() =>
      _LinkedPlainBodyScrollViewState();
}

class _LinkedPlainBodyScrollViewState
    extends State<_LinkedPlainBodyScrollView> {
  final _bodyScrollController = ScrollController();
  bool _isBodyScrollable = false;

  @override
  void initState() {
    super.initState();
    _bodyScrollController.addListener(_refreshScrollability);
  }

  @override
  void didUpdateWidget(covariant _LinkedPlainBodyScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _queueScrollabilityCheck();
  }

  @override
  void dispose() {
    _bodyScrollController
      ..removeListener(_refreshScrollability)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _queueScrollabilityCheck();
    final viewportHeight = (MediaQuery.sizeOf(context).height * 0.52)
        .clamp(220.0, 460.0)
        .toDouble();

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _applyScrollDelta(event.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        key: const ValueKey('message-body-linked-scroll-view'),
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) => _applyScrollDelta(-details.delta.dy),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: viewportHeight),
          child: Scrollbar(
            key: const ValueKey('message-body-inner-scrollbar'),
            controller: _bodyScrollController,
            thumbVisibility: _isBodyScrollable,
            trackVisibility: false,
            thickness: 2,
            radius: const Radius.circular(999),
            child: SingleChildScrollView(
              key: const ValueKey('message-body-inner-scroll-view'),
              controller: _bodyScrollController,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(right: _isBodyScrollable ? 10 : 0),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  void _applyScrollDelta(double scrollDelta) {
    var remainingDelta = scrollDelta;

    if (_bodyScrollController.hasClients) {
      final position = _bodyScrollController.position;
      final currentOffset = position.pixels;
      final nextOffset = (currentOffset + remainingDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final consumedDelta = nextOffset - currentOffset;
      if (consumedDelta.abs() > 0.01) {
        _bodyScrollController.jumpTo(nextOffset);
      }
      remainingDelta -= consumedDelta;
    }

    if (remainingDelta.abs() <= 0.01 ||
        !widget.outerScrollController.hasClients) {
      return;
    }

    final outerPosition = widget.outerScrollController.position;
    final currentOuterOffset = outerPosition.pixels;
    final nextOuterOffset = (currentOuterOffset + remainingDelta).clamp(
      outerPosition.minScrollExtent,
      outerPosition.maxScrollExtent,
    );
    if ((nextOuterOffset - currentOuterOffset).abs() > 0.01) {
      widget.outerScrollController.jumpTo(nextOuterOffset);
    }
  }

  void _queueScrollabilityCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshScrollability();
      }
    });
  }

  void _refreshScrollability() {
    if (!_bodyScrollController.hasClients) {
      return;
    }
    final nextIsScrollable =
        _bodyScrollController.position.maxScrollExtent > 0.5;
    if (nextIsScrollable != _isBodyScrollable && mounted) {
      setState(() => _isBodyScrollable = nextIsScrollable);
    }
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
  String? _loadedHtml;

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
      ..loadHtmlString(_wrapAndTrack(widget.html));
  }

  @override
  void didUpdateWidget(covariant _EmailHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html && _loadedHtml != widget.html) {
      _controller.loadHtmlString(_wrapAndTrack(widget.html));
    }
  }

  String _wrapAndTrack(String rawHtml) {
    _loadedHtml = rawHtml;
    return wrapEmailHtmlForRendering(rawHtml);
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

String wrapEmailHtmlForRendering(String rawHtml) {
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style data-finestar-email-fit>
$_emailFitToWidthCss
  </style>
</head>
<body>
$rawHtml
<style data-finestar-email-fit>
$_emailFitToWidthCss
</style>
</body>
</html>
''';
}

const _emailFitToWidthCss = r'''
    html,
    body {
      margin: 0 !important;
      padding: 0 !important;
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
      background: #ffffff;
      color: #222222;
      overflow-x: auto;
    }

    *,
    *::before,
    *::after {
      box-sizing: border-box !important;
    }

    body {
      overflow-wrap: anywhere;
      word-break: break-word;
      -webkit-text-size-adjust: 100%;
    }

    body > *,
    div,
    section,
    article,
    header,
    footer {
      max-width: 100% !important;
      min-width: 0 !important;
    }

    table,
    table[width],
    table[style*="width"],
    .full-header,
    .mj-outlook-group-fix {
      width: 100% !important;
      max-width: 100% !important;
      min-width: 0 !important;
    }

    td,
    th,
    td[width],
    th[width],
    td[style*="width"],
    th[style*="width"] {
      max-width: 100% !important;
      min-width: 0 !important;
    }

    img,
    picture,
    video,
    canvas,
    svg {
      max-width: 100% !important;
      height: auto !important;
    }

    img[width],
    img[style*="width"] {
      width: auto !important;
      max-width: 100% !important;
    }

    pre,
    code {
      max-width: 100% !important;
      overflow-x: auto !important;
      -webkit-overflow-scrolling: touch;
    }

    pre {
      white-space: pre-wrap !important;
      overflow-wrap: anywhere !important;
    }

    @media only screen and (max-width: 700px) {
      table,
      table[width],
      table[style*="width"],
      .full-header,
      .mj-outlook-group-fix {
        width: 100% !important;
        max-width: 100% !important;
        min-width: 0 !important;
      }

      td,
      th {
        max-width: 100% !important;
      }

      pre,
      code {
        overflow-x: auto !important;
        -webkit-overflow-scrolling: touch;
      }
    }
''';

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
      .where((attachment) => _isVisibleAttachment(message.bodyHtml, attachment))
      .toList();
}

bool _isVisibleAttachment(String? html, MailMessageAttachment attachment) {
  final isVisible = attachment.isVisible;
  if (isVisible != null) {
    return isVisible;
  }
  return !_isReferencedInlineCidResource(html, attachment);
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
