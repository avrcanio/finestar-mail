import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:finestar_mail/core/widgets/app_scaffold.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';

import '../domain/entities/reply_context.dart';
import 'compose_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final attachments = ref.watch(composeControllerProvider);
    final selectedAttachments = attachments.asData?.value ?? const [];

    return AppScaffold(
      title: widget.replyContext == null ? 'Compose' : 'Reply',
      actions: [
        IconButton(onPressed: _send, icon: const Icon(Icons.send_outlined)),
      ],
      child: ListView(
        children: [
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _toController,
                  decoration: const InputDecoration(labelText: 'To'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ccController,
                  decoration: const InputDecoration(labelText: 'CC'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bccController,
                  decoration: const InputDecoration(labelText: 'BCC'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(labelText: 'Message'),
                  minLines: 10,
                  maxLines: 14,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attachments',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton.icon(
                      onPressed: () {
                        ref
                            .read(composeControllerProvider.notifier)
                            .pickAttachments();
                      },
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (selectedAttachments.isEmpty)
                  const Text('No attachments selected.')
                else
                  ...selectedAttachments.map(
                    (file) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(file.fileName),
                      subtitle: Text(file.filePath),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
