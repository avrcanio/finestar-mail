import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route.dart';
import '../../../core/platform/share_intent_service.dart';
import '../../attachments/domain/entities/attachment_ref.dart';
import '../../auth/domain/entities/mail_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/share_compose_args.dart';

const _background = Color(0xFFF7F8FC);
const _primary = Color(0xFF153B52);
const _muted = Color(0xFF5D636B);

class ShareComposeEntryScreen extends ConsumerWidget {
  const ShareComposeEntryScreen({super.key, required this.files});

  final List<SharedFile> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final router = GoRouter.of(context);

    if (files.isEmpty) {
      return const Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Center(child: Text('Nothing to attach.')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: accountsAsync.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                router.go(AppRoute.login.path);
              });
              return const Center(child: CircularProgressIndicator());
            }

            if (accounts.length == 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _openComposeFor(
                  router: router,
                  account: accounts.single,
                  files: files,
                );
              });
              return const Center(child: CircularProgressIndicator());
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Send from',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: const Color(0xFF202124),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick an account for this message only.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: _muted),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: accounts.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final account = accounts[index];
                        return _AccountTile(
                          account: account,
                          onTap: () => _openComposeFor(
                            router: router,
                            account: account,
                            files: files,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  void _openComposeFor({
    required GoRouter router,
    required MailAccount account,
    required List<SharedFile> files,
  }) {
    final attachments = files.map(_attachmentFromSharedFile).toList();
    router.go(
      AppRoute.compose.path,
      extra: ShareComposeArgs(
        accountId: account.id,
        fromEmail: account.email,
        attachments: attachments,
      ),
    );
  }

  AttachmentRef _attachmentFromSharedFile(SharedFile file) {
    return AttachmentRef(
      id: 'share:${DateTime.now().microsecondsSinceEpoch}:${file.path.hashCode}',
      fileName: file.name,
      filePath: file.path,
      sizeBytes: file.sizeBytes,
      mimeType: file.mimeType,
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.onTap});

  final MailAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFE8EFF8),
                child: Icon(Icons.person_outline, color: _primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName.trim().isEmpty
                          ? account.email
                          : account.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF202124),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: _muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _primary),
            ],
          ),
        ),
      ),
    );
  }
}

