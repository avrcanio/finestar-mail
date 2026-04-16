import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attachments/domain/entities/attachment_ref.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/reply_context.dart';
import 'compose_controller.dart';

enum _AttachmentAction { photos, camera, files, drive }

enum _ComposeMoreAction {
  scheduleSend,
  addFromContacts,
  confidentialMode,
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
  const ComposeScreen({super.key, this.replyContext});

  final ReplyContext? replyContext;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _toController;
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  late final TextEditingController _subjectController;
  final _bodyController = TextEditingController();

  bool _showCcBcc = false;

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
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String _prefixFor(ReplyAction action) {
    return switch (action) {
      ReplyAction.reply || ReplyAction.replyAll => 'Re: ',
      ReplyAction.forward => 'Fwd: ',
    };
  }

  Future<void> _send() async {
    final result = await ref
        .read(composeControllerProvider.notifier)
        .send(
          to: _splitAddresses(_toController.text),
          cc: _splitAddresses(_ccController.text),
          bcc: _splitAddresses(_bccController.text),
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
          replyContext: widget.replyContext,
        );

    if (!mounted) {
      return;
    }

    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message queued for delivery.')),
        );
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final activeAccount = ref.watch(activeAccountProvider).asData?.value;
    final attachmentsAsync = ref.watch(composeControllerProvider);
    final selectedAttachments = attachmentsAsync.asData?.value ?? const [];
    final from = activeAccount?.email ?? 'No account selected';

    return Scaffold(
      backgroundColor: _composeBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: _ComposeToolbar(
                onBack: () => Navigator.of(context).pop(),
                onSend: _send,
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
                            label: 'To',
                            controller: _toController,
                            textInputAction: TextInputAction.next,
                            trailing: IconButton(
                              tooltip: 'Show Cc and Bcc',
                              onPressed: () =>
                                  setState(() => _showCcBcc = !_showCcBcc),
                              icon: Icon(
                                _showCcBcc
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: _composeMuted,
                              ),
                            ),
                          ),
                          if (_showCcBcc) ...[
                            _ComposeInputRow(
                              label: 'Cc',
                              controller: _ccController,
                              textInputAction: TextInputAction.next,
                            ),
                            _ComposeInputRow(
                              label: 'Bcc',
                              controller: _bccController,
                              textInputAction: TextInputAction.next,
                            ),
                          ],
                          _ComposeInputRow(
                            label: 'Subject',
                            controller: _subjectController,
                            textInputAction: TextInputAction.next,
                            isSubject: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                            child: TextField(
                              controller: _bodyController,
                              decoration: InputDecoration(
                                hintText: 'Compose email',
                                hintStyle: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: _composeMuted,
                                      fontSize: 16,
                                      letterSpacing: 0.1,
                                    ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontSize: 16, letterSpacing: 0.1),
                              minLines: 12,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                            ),
                          ),
                          if (attachmentsAsync.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: LinearProgressIndicator(),
                            ),
                          if (selectedAttachments.isNotEmpty)
                            _AttachmentList(attachments: selectedAttachments),
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
    );
  }
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
    required this.label,
    required this.controller,
    this.trailing,
    this.textInputAction,
    this.isSubject = false,
  });

  final String label;
  final TextEditingController controller;
  final Widget? trailing;
  final TextInputAction? textInputAction;
  final bool isSubject;

  @override
  Widget build(BuildContext context) {
    return _ComposeRowShell(
      label: label,
      trailing: trailing,
      child: TextField(
        controller: controller,
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

  final List<AttachmentRef> attachments;

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
    _ComposeMoreAction.saveDraft => 'Save draft',
    _ComposeMoreAction.discard => 'Discard',
    _ComposeMoreAction.settings => 'Settings',
    _ComposeMoreAction.helpFeedback => 'Help & feedback',
  };
}
