import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_route.dart';
import '../../../data/remote/backend_mail_api_client.dart';
import '../../contacts/domain/entities/contact_suggestion.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/data/backend_auth_token_selector.dart';
import '../domain/entities/compose_attachment.dart';
import '../domain/entities/reply_context.dart';
import '../domain/entities/share_compose_args.dart';
import 'compose_controller.dart';

enum _AttachmentAction { photos, camera, files, drive }

enum _RecipientField { to, cc, bcc }

enum _ComposeMoreAction {
  scheduleSend,
  addFromContacts,
  confidentialMode,
  r1Receipt,
  saveDraft,
  discard,
  settings,
  helpFeedback,
}

const _composeBackground = Color(0xFFF7F8FC);
const _composeCard = Colors.white;
const _composeStroke = Color(0xFFE8EFF8);
const _composeMuted = Color(0xFF5D636B);
const _composeChip = Color(0xFFCFE7FA);

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, this.replyContext, this.shareArgs});

  final ReplyContext? replyContext;
  final ShareComposeArgs? shareArgs;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _toController;
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  final _toFocusNode = FocusNode();
  final _ccFocusNode = FocusNode();
  final _bccFocusNode = FocusNode();

  bool _showCcBcc = false;
  bool _sending = false;
  bool _ocrRunning = false;
  Timer? _recipientSuggestionDebounce;
  int _recipientSuggestionRequestId = 0;
  _RecipientField? _suggestionField;
  List<ContactSuggestion> _contactSuggestions = const [];

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(
      text: widget.replyContext?.recipients.join(', ') ?? '',
    );
    _subjectController = TextEditingController(
      text: widget.replyContext == null
          ? ''
          : '${_prefixFor(widget.replyContext!.action)}${widget.replyContext!.subject}',
    );
    _bodyController = TextEditingController(
      text: widget.replyContext == null
          ? ''
          : '\n\n${_quotedTextFor(widget.replyContext!)}',
    );
    if (widget.replyContext?.action == ReplyAction.forward &&
        widget.replyContext!.forwardedAttachments.isNotEmpty) {
      Future<void>(() {
        if (!mounted) {
          return;
        }
        ref
            .read(composeControllerProvider.notifier)
            .setForwardedAttachments(widget.replyContext!.forwardedAttachments);
      });
    }
    final shareArgs = widget.shareArgs;
    if (shareArgs != null && shareArgs.attachments.isNotEmpty) {
      Future<void>(() {
        if (!mounted) {
          return;
        }
        ref
            .read(composeControllerProvider.notifier)
            .addLocalAttachments(shareArgs.attachments);
      });
    }
    _toFocusNode.addListener(
      () => _handleRecipientFocusChanged(_RecipientField.to),
    );
    _ccFocusNode.addListener(
      () => _handleRecipientFocusChanged(_RecipientField.cc),
    );
    _bccFocusNode.addListener(
      () => _handleRecipientFocusChanged(_RecipientField.bcc),
    );
  }

  @override
  void dispose() {
    _recipientSuggestionDebounce?.cancel();
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _toFocusNode.dispose();
    _ccFocusNode.dispose();
    _bccFocusNode.dispose();
    super.dispose();
  }

  String _prefixFor(ReplyAction action) {
    return switch (action) {
      ReplyAction.reply || ReplyAction.replyAll => 'Re: ',
      ReplyAction.forward => 'Fwd: ',
    };
  }

  String _quotedTextFor(ReplyContext context) {
    final formattedDate = DateFormat(
      'EEE, MMM d, y HH:mm',
    ).format(context.originalReceivedAt);
    final header = switch (context.action) {
      ReplyAction.reply || ReplyAction.replyAll =>
        'On $formattedDate ${context.originalSender} wrote:',
      ReplyAction.forward =>
        '---------- Forwarded message ----------\nFrom: ${context.originalSender}\nDate: $formattedDate\nSubject: ${context.subject}',
    };
    final quotedBody = context.originalBody
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => '> $line')
        .join('\n');
    return '$header\n$quotedBody';
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(composeControllerProvider.notifier)
        .send(
          to: _splitAddresses(_toController.text),
          cc: _splitAddresses(_ccController.text),
          bcc: _splitAddresses(_bccController.text),
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
          replyContext: widget.replyContext,
          accountIdOverride: widget.shareArgs?.accountId,
        );

    if (!mounted) {
      return;
    }
    setState(() => _sending = false);

    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message queued for delivery.')),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoute.inbox.path);
        }
      },
      failure: (message) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message))),
    );
  }

  List<String> _splitAddresses(String raw) {
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  void _handleRecipientFocusChanged(_RecipientField field) {
    if (_focusNodeFor(field).hasFocus) {
      _scheduleRecipientSuggestions(field);
      return;
    }
    if (_suggestionField == field) {
      _hideRecipientSuggestions();
    }
  }

  void _scheduleRecipientSuggestions(_RecipientField field) {
    final focusNode = _focusNodeFor(field);
    if (!focusNode.hasFocus) {
      return;
    }

    final controller = _controllerFor(field);
    final segment = _activeRecipientSegment(controller);
    final query = segment.query;
    _recipientSuggestionRequestId++;
    _recipientSuggestionDebounce?.cancel();

    if (query.length < 3) {
      _hideRecipientSuggestions();
      return;
    }

    final requestId = _recipientSuggestionRequestId;
    _recipientSuggestionDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadRecipientSuggestions(
        field: field,
        query: query,
        requestId: requestId,
      );
    });
  }

  Future<void> _loadRecipientSuggestions({
    required _RecipientField field,
    required String query,
    required int requestId,
  }) async {
    final suggestions = await ref
        .read(contactsRepositoryProvider)
        .suggestContacts(query);
    if (!mounted ||
        requestId != _recipientSuggestionRequestId ||
        !_focusNodeFor(field).hasFocus) {
      return;
    }

    final currentQuery = _activeRecipientSegment(_controllerFor(field)).query;
    if (currentQuery != query) {
      return;
    }

    setState(() {
      _suggestionField = suggestions.isEmpty ? null : field;
      _contactSuggestions = suggestions;
    });
  }

  void _hideRecipientSuggestions() {
    _recipientSuggestionDebounce?.cancel();
    if (_suggestionField == null && _contactSuggestions.isEmpty) {
      return;
    }
    setState(() {
      _suggestionField = null;
      _contactSuggestions = const [];
    });
  }

  void _selectRecipientSuggestion(
    _RecipientField field,
    ContactSuggestion suggestion,
  ) {
    final controller = _controllerFor(field);
    final segment = _activeRecipientSegment(controller);
    final replacement =
        '${segment.start > 0 ? ' ' : ''}${suggestion.recipientText}, ';
    final nextText =
        controller.text.substring(0, segment.start) +
        replacement +
        controller.text.substring(segment.end);
    final nextOffset = segment.start + replacement.length;
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _recipientSuggestionRequestId++;
    _hideRecipientSuggestions();
  }

  TextEditingController _controllerFor(_RecipientField field) {
    return switch (field) {
      _RecipientField.to => _toController,
      _RecipientField.cc => _ccController,
      _RecipientField.bcc => _bccController,
    };
  }

  FocusNode _focusNodeFor(_RecipientField field) {
    return switch (field) {
      _RecipientField.to => _toFocusNode,
      _RecipientField.cc => _ccFocusNode,
      _RecipientField.bcc => _bccFocusNode,
    };
  }

  _RecipientSegment _activeRecipientSegment(TextEditingController controller) {
    final text = controller.text;
    final selectionOffset = controller.selection.baseOffset;
    final cursor = selectionOffset < 0 ? text.length : selectionOffset;
    final boundedCursor = cursor.clamp(0, text.length);
    final previousComma = boundedCursor <= 0
        ? -1
        : text.lastIndexOf(',', boundedCursor - 1);
    final nextComma = text.indexOf(',', boundedCursor);
    final start = previousComma == -1 ? 0 : previousComma + 1;
    final end = nextComma == -1 ? text.length : nextComma;
    return _RecipientSegment(
      start: start,
      end: end,
      query: text.substring(start, end).trim(),
    );
  }

  Future<void> _handleAttachmentAction(_AttachmentAction action) async {
    final controller = ref.read(composeControllerProvider.notifier);
    switch (action) {
      case _AttachmentAction.photos:
        await controller.pickPhotos();
      case _AttachmentAction.camera:
        await controller.takePhoto();
      case _AttachmentAction.files:
        await controller.pickFiles();
      case _AttachmentAction.drive:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nextcloud Drive coming later.')),
          );
        }
    }
  }

  Future<void> _handleMoreAction(_ComposeMoreAction action) async {
    switch (action) {
      case _ComposeMoreAction.r1Receipt:
        await _handleR1Receipt();
      case _ComposeMoreAction.discard:
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard draft?'),
            content: const Text('This compose draft will be closed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldDiscard == true && mounted) {
          Navigator.of(context).pop();
        }
      case _:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_moreActionLabel(action)} coming later.'),
            ),
          );
        }
    }
  }

  Future<void> _handleR1Receipt() async {
    if (_ocrRunning) {
      return;
    }

    setState(() => _ocrRunning = true);
    try {
      final selected = await ref
          .read(backendAuthTokenSelectorProvider)
          .selectToken();
      if (!mounted) {
        return;
      }
      if (selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in before using R1 račun.')),
        );
        return;
      }

      final scanned = await ref
          .read(documentScannerServiceProvider)
          .scanFirstPageAsImage();
      if (!mounted) {
        return;
      }
      if (scanned == null) {
        return;
      }

      final result = await ref.read(backendMailApiClientProvider).receiptOcr(
            token: selected.token,
            imageBytes: scanned.bytes,
            contentType: scanned.contentType,
            filename: scanned.filename,
            requestTimeout: const Duration(seconds: 120),
          );

      if (!mounted) {
        return;
      }

      // New API contract (issue #43): JSON part can be a wrapper:
      // { receipt: {...}, draft: {subject, body}, artifacts_dir, warnings, ... }
      final receiptJson = _extractReceiptPayload(result.json);
      final warnings = _extractWarnings(result.json);
      if (warnings.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt OCR warnings: ${warnings.join(', ')}')),
        );
      }
      final effectiveReceiptJson =
          await _ensurePaymentSelectionIfMissing(receiptJson);
      if (!mounted) {
        return;
      }
      final effectiveResponseJson = _mergeReceiptIntoResponseJson(
        result.json,
        effectiveReceiptJson,
      );

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final jsonFilename = 'r1_$timestamp.json';
      final pdfFilename = _safeFilename(result.pdfFilename, fallback: 'r1_$timestamp.pdf');

      final jsonPath = p.join(tempDir.path, jsonFilename);
      final pdfPath = p.join(tempDir.path, pdfFilename);

      // Persist the full JSON wrapper for debugging / future use.
      final jsonBytes = utf8.encode(jsonEncode(effectiveResponseJson));
      await File(jsonPath).writeAsBytes(jsonBytes, flush: true);
      await File(pdfPath).writeAsBytes(result.pdfBytes, flush: true);

      final jsonSize = await File(jsonPath).length();
      final pdfSize = await File(pdfPath).length();

      ref.read(composeControllerProvider.notifier).addLocalAttachments([
            AttachmentRef(
              id: 'r1:$timestamp:json',
              fileName: jsonFilename,
              filePath: jsonPath,
              sizeBytes: jsonSize,
              mimeType: 'application/json',
            ),
            AttachmentRef(
              id: 'r1:$timestamp:pdf',
              fileName: pdfFilename,
              filePath: pdfPath,
              sizeBytes: pdfSize,
              mimeType: 'application/pdf',
            ),
          ]);

      final draft = _extractDraft(result.json);
      final draftSubject = (draft?['subject']?.toString() ?? '').trim();
      final draftBody = (draft?['body']?.toString() ?? '').trim();

      if (draftSubject.isNotEmpty || draftBody.isNotEmpty) {
        if (draftSubject.isNotEmpty) {
          _subjectController.text = draftSubject;
        }
        if (draftBody.isNotEmpty) {
          _bodyController.text = draftBody;
        }
      } else {
        final mapping = _r1SubjectAndBodyFromJson(effectiveReceiptJson);
        if (mapping != null) {
          _subjectController.text = mapping.subject;
          _bodyController.text = mapping.body;
        } else {
          final ocrText = _extractOcrText(result.json);
          if (ocrText.isNotEmpty) {
            _bodyController.text = ocrText;
          }
        }
      }
    } on BackendMailApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to OCR receipt: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _ocrRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAccount = ref.watch(activeAccountProvider).asData?.value;
    final attachmentsAsync = ref.watch(composeControllerProvider);
    final selectedAttachments = attachmentsAsync.asData?.value ?? const [];
    final from =
        widget.shareArgs?.fromEmail ??
        activeAccount?.email ??
        'No account selected';

    return Scaffold(
      backgroundColor: _composeBackground,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideRecipientSuggestions,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: _ComposeToolbar(
                      onBack: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoute.inbox.path);
                        }
                      },
                      onSend: _sending ? () {} : _send,
                      onAttachmentSelected: _handleAttachmentAction,
                      onMoreSelected: _handleMoreAction,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      children: [
                        Material(
                          color: _composeCard,
                          elevation: 0,
                          borderRadius: BorderRadius.circular(26),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Column(
                              children: [
                                _ReadonlyComposeRow(label: 'From', value: from),
                                _ComposeInputRow(
                                  key: const ValueKey('compose-to-row'),
                                  label: 'To',
                                  controller: _toController,
                                  fieldKey: const ValueKey('compose-to-field'),
                                  focusNode: _toFocusNode,
                                  onChanged: (_) =>
                                      _scheduleRecipientSuggestions(
                                        _RecipientField.to,
                                      ),
                                  textInputAction: TextInputAction.next,
                                  trailing: IconButton(
                                    tooltip: 'Show Cc and Bcc',
                                    onPressed: _sending
                                        ? null
                                        : () => setState(
                                          () => _showCcBcc = !_showCcBcc,
                                        ),
                                    icon: Icon(
                                      _showCcBcc
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: _composeMuted,
                                    ),
                                  ),
                                ),
                                if (_suggestionField == _RecipientField.to)
                                  _ContactSuggestionList(
                                    suggestions: _contactSuggestions,
                                    onSelected: (suggestion) =>
                                        _selectRecipientSuggestion(
                                          _RecipientField.to,
                                          suggestion,
                                        ),
                                  ),
                                if (_showCcBcc) ...[
                                  _ComposeInputRow(
                                    key: const ValueKey('compose-cc-row'),
                                    label: 'Cc',
                                    controller: _ccController,
                                    fieldKey: const ValueKey(
                                      'compose-cc-field',
                                    ),
                                    focusNode: _ccFocusNode,
                                    onChanged: (_) =>
                                        _scheduleRecipientSuggestions(
                                          _RecipientField.cc,
                                        ),
                                    textInputAction: TextInputAction.next,
                                  ),
                                  if (_suggestionField == _RecipientField.cc)
                                    _ContactSuggestionList(
                                      suggestions: _contactSuggestions,
                                      onSelected: (suggestion) =>
                                          _selectRecipientSuggestion(
                                            _RecipientField.cc,
                                            suggestion,
                                          ),
                                    ),
                                  _ComposeInputRow(
                                    key: const ValueKey('compose-bcc-row'),
                                    label: 'Bcc',
                                    controller: _bccController,
                                    fieldKey: const ValueKey(
                                      'compose-bcc-field',
                                    ),
                                    focusNode: _bccFocusNode,
                                    onChanged: (_) =>
                                        _scheduleRecipientSuggestions(
                                          _RecipientField.bcc,
                                        ),
                                    textInputAction: TextInputAction.next,
                                  ),
                                  if (_suggestionField == _RecipientField.bcc)
                                    _ContactSuggestionList(
                                      suggestions: _contactSuggestions,
                                      onSelected: (suggestion) =>
                                          _selectRecipientSuggestion(
                                            _RecipientField.bcc,
                                            suggestion,
                                          ),
                                    ),
                                ],
                                _ComposeInputRow(
                                  label: 'Subject',
                                  controller: _subjectController,
                                  fieldKey: const ValueKey(
                                    'compose-subject-field',
                                  ),
                                  textInputAction: TextInputAction.next,
                                  isSubject: true,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    18,
                                    22,
                                    12,
                                  ),
                                  child: TextField(
                                    controller: _bodyController,
                                    decoration: InputDecoration(
                                      hintText: 'Compose email',
                                      hintStyle: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: _composeMuted,
                                            fontSize: 16,
                                            letterSpacing: 0.1,
                                          ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          fontSize: 16,
                                          letterSpacing: 0.1,
                                        ),
                                    minLines: 12,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                  ),
                                ),
                                if (attachmentsAsync.isLoading)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: LinearProgressIndicator(),
                                  ),
                                if (selectedAttachments.isNotEmpty)
                                  _AttachmentList(
                                    attachments: selectedAttachments,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_sending) const _SendingOverlay(),
          if (_ocrRunning) const _BlockingOverlay(text: 'Processing R1…'),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _ensurePaymentSelectionIfMissing(
    Map<String, dynamic> json,
  ) async {
    final payment = json['payment'];
    final method =
        payment is Map ? (payment['method']?.toString() ?? '').trim() : '';
    final brand =
        payment is Map ? (payment['card_brand']?.toString() ?? '').trim() : '';

    final needsPrompt =
        method.isEmpty || (method.toLowerCase() == 'card' && brand.isEmpty);
    if (!needsPrompt) {
      return json;
    }

    final selection = await showDialog<_R1PaymentSelection>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Način plaćanja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Odaberi kako je račun plaćen.'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gotovina'),
              onTap: () =>
                  Navigator.of(context).pop(_R1PaymentSelection.cash),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visa'),
              onTap: () =>
                  Navigator.of(context).pop(_R1PaymentSelection.visa),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mastercard'),
              onTap: () =>
                  Navigator.of(context).pop(_R1PaymentSelection.mastercard),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Preskoči'),
          ),
        ],
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
    );

    // If user cancels or skips, keep original JSON (no payment line).
    if (selection == null) {
      return json;
    }

    final next = Map<String, dynamic>.from(json);
    final nextPayment = payment is Map<String, dynamic>
        ? Map<String, dynamic>.from(payment)
        : <String, dynamic>{};
    switch (selection) {
      case _R1PaymentSelection.cash:
        nextPayment['method'] = 'cash';
        nextPayment.remove('card_brand');
      case _R1PaymentSelection.visa:
        nextPayment['method'] = 'card';
        nextPayment['card_brand'] = 'Visa';
      case _R1PaymentSelection.mastercard:
        nextPayment['method'] = 'card';
        nextPayment['card_brand'] = 'Mastercard';
    }
    next['payment'] = nextPayment;
    return next;
  }

  Map<String, dynamic> _extractReceiptPayload(Map<String, dynamic> json) {
    final receipt = json['receipt'];
    if (receipt is Map<String, dynamic>) {
      return receipt;
    }
    if (receipt is Map) {
      return Map<String, dynamic>.from(receipt);
    }
    return json;
  }

  Map<String, dynamic>? _extractDraft(Map<String, dynamic> json) {
    final draft = json['draft'];
    if (draft is Map<String, dynamic>) {
      return draft;
    }
    if (draft is Map) {
      return Map<String, dynamic>.from(draft);
    }
    return null;
  }

  List<String> _extractWarnings(Map<String, dynamic> json) {
    final raw = json['warnings'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return const [];
  }

  String _extractOcrText(Map<String, dynamic> json) {
    final raw = json['ocr_text'];
    if (raw == null) {
      return '';
    }
    final text = raw.toString().trim();
    if (text.isEmpty) {
      return '';
    }
    // Keep body bounded; user can open JSON attachment for full content.
    const maxChars = 8000;
    if (text.length <= maxChars) {
      return text;
    }
    return '${text.substring(0, maxChars)}…';
  }

  Map<String, dynamic> _mergeReceiptIntoResponseJson(
    Map<String, dynamic> responseJson,
    Map<String, dynamic> effectiveReceipt,
  ) {
    if (!responseJson.containsKey('receipt')) {
      return responseJson;
    }
    final next = Map<String, dynamic>.from(responseJson);
    next['receipt'] = effectiveReceipt;
    return next;
  }
}

enum _R1PaymentSelection { cash, visa, mastercard }

class _BlockingOverlay extends StatelessWidget {
  const _BlockingOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      text,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF20242A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendingOverlay extends StatelessWidget {
  const _SendingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Sending…',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF20242A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientSegment {
  const _RecipientSegment({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class _ComposeToolbar extends StatelessWidget {
  const _ComposeToolbar({
    required this.onBack,
    required this.onSend,
    required this.onAttachmentSelected,
    required this.onMoreSelected,
  });

  final VoidCallback onBack;
  final VoidCallback onSend;
  final ValueChanged<_AttachmentAction> onAttachmentSelected;
  final ValueChanged<_ComposeMoreAction> onMoreSelected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(28),
      color: _composeCard,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              color: primary,
              icon: const Icon(Icons.arrow_back, size: 28),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'New message',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const Spacer(),
            PopupMenuButton<_AttachmentAction>(
              tooltip: 'Attach',
              color: _composeCard,
              iconColor: primary,
              icon: const Icon(Icons.attach_file, size: 26),
              onSelected: onAttachmentSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _AttachmentAction.photos,
                  child: _PopupRow(icon: Icons.photo_outlined, label: 'Photos'),
                ),
                PopupMenuItem(
                  value: _AttachmentAction.camera,
                  child: _PopupRow(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                  ),
                ),
                PopupMenuItem(
                  value: _AttachmentAction.files,
                  child: _PopupRow(
                    icon: Icons.insert_drive_file_outlined,
                    label: 'Files',
                  ),
                ),
                PopupMenuItem(
                  value: _AttachmentAction.drive,
                  child: _PopupRow(
                    icon: Icons.change_history_outlined,
                    label: 'Drive',
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Send',
              onPressed: onSend,
              color: primary,
              icon: const Icon(Icons.send_outlined, size: 30),
            ),
            PopupMenuButton<_ComposeMoreAction>(
              tooltip: 'More options',
              color: _composeCard,
              iconColor: primary,
              icon: const Icon(Icons.more_vert, size: 28),
              onSelected: onMoreSelected,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _ComposeMoreAction.scheduleSend,
                  child: Text('Schedule send'),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.addFromContacts,
                  child: Text('Add from Contacts'),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.confidentialMode,
                  child: Text('Confidential mode'),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.r1Receipt,
                  child: Text('R1 račun'),
                ),
                PopupMenuItem(
                  value: _ComposeMoreAction.saveDraft,
                  enabled: false,
                  child: Text(
                    'Save draft',
                    style: TextStyle(color: Theme.of(context).disabledColor),
                  ),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.discard,
                  child: Text('Discard'),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.settings,
                  child: Text('Settings'),
                ),
                const PopupMenuItem(
                  value: _ComposeMoreAction.helpFeedback,
                  child: Text('Help & feedback'),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 20),
          Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 18,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadonlyComposeRow extends StatelessWidget {
  const _ReadonlyComposeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _ComposeRowShell(
      label: label,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF20242A),
          fontWeight: FontWeight.w500,
          fontSize: 16,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _ComposeInputRow extends StatelessWidget {
  const _ComposeInputRow({
    super.key,
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.trailing,
    this.focusNode,
    this.onChanged,
    this.textInputAction,
    this.isSubject = false,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final Widget? trailing;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool isSubject;

  @override
  Widget build(BuildContext context) {
    return _ComposeRowShell(
      label: label,
      trailing: trailing,
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _composeMuted,
            fontWeight: FontWeight.w500,
            fontSize: 16,
            letterSpacing: 0.1,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF20242A),
          fontWeight: FontWeight.w500,
          fontSize: 16,
          letterSpacing: 0.1,
        ),
        textInputAction: textInputAction,
        keyboardType: TextInputType.emailAddress,
      ),
    );
  }
}

class _ContactSuggestionList extends StatelessWidget {
  const _ContactSuggestionList({
    required this.suggestions,
    required this.onSelected,
  });

  final List<ContactSuggestion> suggestions;
  final ValueChanged<ContactSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _composeCard,
        border: Border(bottom: BorderSide(color: _composeStroke)),
      ),
      padding: const EdgeInsets.fromLTRB(80, 4, 12, 8),
      child: Material(
        color: _composeCard,
        elevation: 4,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: suggestions.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: _composeStroke),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              final displayName = suggestion.displayName?.trim();
              final hasName = displayName != null && displayName.isNotEmpty;
              return InkWell(
                onTap: () => onSelected(suggestion),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              suggestion.displayLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF20242A),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                  ),
                            ),
                            if (hasName)
                              Text(
                                suggestion.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: _composeMuted,
                                      letterSpacing: 0.1,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ComposeRowShell extends StatelessWidget {
  const _ComposeRowShell({
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _composeStroke)),
      ),
      padding: const EdgeInsets.only(left: 22, right: 12),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _composeMuted,
                fontWeight: FontWeight.w500,
                fontSize: 15,
                letterSpacing: 0.1,
              ),
            ),
          ),
          Expanded(child: child),
          ?trailing,
        ],
      ),
    );
  }
}

class _AttachmentList extends ConsumerWidget {
  const _AttachmentList({required this.attachments});

  final List<ComposeAttachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in attachments)
            InputChip(
              backgroundColor: _composeChip,
              side: BorderSide.none,
              label: Text(attachment.fileName),
              labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              avatar: Icon(
                Icons.attach_file,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              onDeleted: () => ref
                  .read(composeControllerProvider.notifier)
                  .removeAttachment(attachment.id),
            ),
        ],
      ),
    );
  }
}

String _moreActionLabel(_ComposeMoreAction action) {
  return switch (action) {
    _ComposeMoreAction.scheduleSend => 'Schedule send',
    _ComposeMoreAction.addFromContacts => 'Add from Contacts',
    _ComposeMoreAction.confidentialMode => 'Confidential mode',
    _ComposeMoreAction.r1Receipt => 'R1 račun',
    _ComposeMoreAction.saveDraft => 'Save draft',
    _ComposeMoreAction.discard => 'Discard',
    _ComposeMoreAction.settings => 'Settings',
    _ComposeMoreAction.helpFeedback => 'Help & feedback',
  };
}

String _safeFilename(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_');
  return sanitized.isEmpty ? fallback : sanitized;
}

class _R1Mapping {
  const _R1Mapping({required this.subject, required this.body});

  final String subject;
  final String body;
}

_R1Mapping? _r1SubjectAndBodyFromJson(Map<String, dynamic> json) {
  final sellerName = _stringAt(json, ['seller', 'name']).trim();
  final sellerOib = _stringAt(json, ['seller', 'oib']).trim();
  final documentType = _stringAt(json, ['invoice', 'document_type']).trim();
  final invoiceNumber = _stringAt(json, ['invoice', 'number']).trim();
  final issueDateRaw = _stringAt(json, ['invoice', 'issue_date']).trim();
  final issueDateFormatted = _formatHrDate(issueDateRaw);
  final currency = _stringAt(json, ['invoice', 'currency']).trim();

  final subjectParts = [sellerName, documentType, invoiceNumber]
      .where((p) => p.trim().isNotEmpty)
      .toList();
  if (subjectParts.isEmpty) {
    return null;
  }
  final subject = subjectParts.join(' ');

  final header = _compactSpaces(
    [
      'u prilogu je',
      if (documentType.isNotEmpty) documentType,
      if (invoiceNumber.isNotEmpty) invoiceNumber,
      if (sellerName.isNotEmpty) 'dobavljača $sellerName',
      if (sellerOib.isNotEmpty) 'OIB: $sellerOib',
      if (issueDateFormatted.isNotEmpty) 'od datuma $issueDateFormatted',
    ].join(' '),
  );

  final lines = _listAt(json, ['lines']);
  final lineTexts = <String>[];
  for (final line in lines) {
    if (line is! Map<String, dynamic>) {
      continue;
    }
    final desc = (line['description']?.toString() ?? '').trim();
    final qty = (line['quantity_l']?.toString() ?? '').trim();
    final unit = (line['unit_price']?.toString() ?? '').trim();
    final net = (line['amount_net']?.toString() ?? '').trim();

    final qtyWithUnit = qty.isEmpty ? '' : '$qty l';
    final hasEquationParts =
        qtyWithUnit.isNotEmpty || unit.isNotEmpty || net.isNotEmpty;
    if (desc.isEmpty && !hasEquationParts) {
      continue;
    }
    final unitWithCurrency = unit.isEmpty ? '' : _amountWithCurrency(unit, currency);
    final netWithCurrency = net.isEmpty ? '' : _amountWithCurrency(net, currency);
    final formatted = _compactSpaces(
      [
        if (desc.isNotEmpty) desc,
        if (qtyWithUnit.isNotEmpty) qtyWithUnit,
        if (unitWithCurrency.isNotEmpty) 'x $unitWithCurrency',
        if (netWithCurrency.isNotEmpty) '= $netWithCurrency',
      ].join(' '),
    );
    if (formatted.isNotEmpty) {
      lineTexts.add(formatted);
    }
  }

  final totalsNet = _stringAt(json, ['totals', 'net']).trim();
  final totalsTax = _stringAt(json, ['totals', 'tax']).trim();
  final totalsGross = _stringAt(json, ['totals', 'gross']).trim();
  final paymentMethod = _stringAt(json, ['payment', 'method']).trim();
  final cardBrand = _stringAt(json, ['payment', 'card_brand']).trim();

  final buffer = StringBuffer()..writeln(header);
  if (lineTexts.isNotEmpty) {
    buffer.writeln();
    for (final line in lineTexts) {
      buffer.writeln(line);
    }
  }
  if (totalsNet.isNotEmpty || totalsTax.isNotEmpty || totalsGross.isNotEmpty) {
    buffer.writeln();
    if (totalsNet.isNotEmpty) {
      buffer.writeln('bez PDV  ${_amountWithCurrency(totalsNet, currency)}');
    }
    if (totalsTax.isNotEmpty) {
      buffer.writeln('PDV  ${_amountWithCurrency(totalsTax, currency)}');
    }
    if (totalsGross.isNotEmpty) {
      buffer.writeln(
        'ukupno sa PDV  ${_amountWithCurrency(totalsGross, currency)}',
      );
    }
  }

  final paymentLine = _paymentLine(paymentMethod, cardBrand);
  if (paymentLine.isNotEmpty) {
    buffer.writeln();
    buffer.writeln(paymentLine);
  }

  return _R1Mapping(subject: subject, body: buffer.toString().trim());
}

String _compactSpaces(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _formatHrDate(String raw) {
  if (raw.trim().isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) {
    return raw.trim();
  }
  final day = parsed.day.toString().padLeft(2, '0');
  final month = parsed.month.toString().padLeft(2, '0');
  final year = parsed.year.toString();
  return '$day.$month.$year';
}

String _amountWithCurrency(String amount, String currency) {
  final a = amount.trim();
  if (a.isEmpty) {
    return '';
  }
  final c = currency.trim();
  return c.isEmpty ? a : '$a $c';
}

String _paymentLine(String method, String cardBrand) {
  final normalized = method.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  final label = switch (normalized) {
    'card' => 'karticom',
    'cash' => 'gotovina',
    'bank_transfer' => 'virman',
    'transfer' => 'virman',
    'wire' => 'virman',
    _ => normalized,
  };
  final brand = _normalizeCardBrand(cardBrand);
  final suffix = brand.isEmpty ? '' : ' ($brand)';
  return 'Plaćeno $label$suffix';
}

String _normalizeCardBrand(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
  if (normalized == 'visa' || normalized.startsWith('visa')) {
    return 'Visa';
  }
  if (normalized == 'mastercard' ||
      normalized == 'master' ||
      normalized == 'mc' ||
      normalized.startsWith('mastercard')) {
    return 'Mastercard';
  }
  if (normalized == 'maestro' || normalized.startsWith('maestro')) {
    return 'Maestro';
  }
  if (normalized == 'amex' ||
      normalized == 'americanexpress' ||
      normalized.startsWith('americanexpress')) {
    return 'Amex';
  }
  if (normalized == 'diners' ||
      normalized == 'dinersclub' ||
      normalized.startsWith('dinersclub')) {
    return 'Diners';
  }

  // Fallback: keep user's value but TitleCase it.
  return trimmed.isEmpty
      ? ''
      : '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
}

String _stringAt(Map<String, dynamic> root, List<String> path) {
  Object? current = root;
  for (final key in path) {
    if (current is Map<String, dynamic>) {
      current = current[key];
    } else {
      return '';
    }
  }
  if (current == null) {
    return '';
  }
  return current.toString();
}

List<Object?> _listAt(Map<String, dynamic> root, List<String> path) {
  Object? current = root;
  for (final key in path) {
    if (current is Map<String, dynamic>) {
      current = current[key];
    } else {
      return const [];
    }
  }
  if (current is List) {
    return current;
  }
  return const [];
}
