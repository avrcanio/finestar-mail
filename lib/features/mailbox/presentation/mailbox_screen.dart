import 'dart:async';

import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:finestar_mail/core/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_route.dart';
import '../../auth/domain/entities/mail_account.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/entities/mail_folder.dart';
import '../domain/entities/mail_message_summary.dart';
import 'mailbox_controller.dart';

class MailboxScreen extends ConsumerStatefulWidget {
  const MailboxScreen({super.key});

  @override
  ConsumerState<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends ConsumerState<MailboxScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();

  Timer? _searchDebounce;
  String? _selectedFolderId;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() => _searchQuery = value.trim());
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final activeAccount = ref.watch(activeAccountProvider).asData?.value;
    final isSearching = _searchQuery.isNotEmpty;
    final folders = ref.watch(foldersProvider).asData?.value ?? const [];
    final selectedFolder = _selectedFolder(folders);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF7F8FC),
      drawer: _MailboxDrawer(
        selectedFolderId: selectedFolder?.id,
        onFolderSelected: (folder) {
          _searchDebounce?.cancel();
          setState(() => _selectedFolderId = folder.id);
          Navigator.of(context).pop();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoute.compose.path),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: _GmailSearchBar(
                controller: _searchController,
                activeAccount: activeAccount,
                isSearching: isSearching,
                onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
                onAvatarPressed: () => context.push(AppRoute.settings.path),
              ),
            ),
            Expanded(
              child: selectedFolder == null
                  ? const Center(child: CircularProgressIndicator())
                  : _MailboxContent(
                      folder: selectedFolder,
                      searchQuery: _searchQuery,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  MailFolder? _selectedFolder(List<MailFolder> folders) {
    if (folders.isEmpty) {
      return null;
    }
    final selectedFolderId = _selectedFolderId;
    if (selectedFolderId != null) {
      for (final folder in folders) {
        if (folder.id == selectedFolderId) {
          return folder;
        }
      }
    }
    for (final folder in folders) {
      if (_isInbox(folder)) {
        return folder;
      }
    }
    return folders.first;
  }
}

class _GmailSearchBar extends StatelessWidget {
  const _GmailSearchBar({
    required this.controller,
    required this.activeAccount,
    required this.isSearching,
    required this.onMenuPressed,
    required this.onChanged,
    required this.onClear,
    required this.onAvatarPressed,
  });

  final TextEditingController controller;
  final MailAccount? activeAccount;
  final bool isSearching;
  final VoidCallback onMenuPressed;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onAvatarPressed;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(activeAccount);

    return Material(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
      color: Colors.white,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Open folders',
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: const InputDecoration(
                  hintText: 'Search in mail',
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (isSearching)
              IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAvatarPressed,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(MailAccount? account) {
    final source = account?.displayName.trim().isNotEmpty == true
        ? account!.displayName
        : account?.email ?? '?';
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _MailboxDrawer extends ConsumerWidget {
  const _MailboxDrawer({
    required this.selectedFolderId,
    required this.onFolderSelected,
  });

  final String? selectedFolderId;
  final ValueChanged<MailFolder> onFolderSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersProvider);

    return Drawer(
      backgroundColor: const Color(0xFFF7F8FC),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
          children: [
            foldersAsync.when(
              data: (folders) {
                final sortedFolders = _sortFolders(folders);
                if (sortedFolders.isEmpty) {
                  return const ListTile(
                    leading: Icon(Icons.folder_off_outlined),
                    title: Text('No folders found'),
                  );
                }

                return Column(
                  children: [
                    for (final folder in sortedFolders)
                      NavigationDrawerDestination(
                        icon: Icon(_folderIcon(folder)),
                        selectedIcon: Icon(_folderIcon(folder)),
                        label: Text(_folderLabel(folder)),
                      )._asListTile(
                        selected:
                            selectedFolderId == folder.id ||
                            (selectedFolderId == null && _isInbox(folder)),
                        onTap: () => onFolderSelected(folder),
                      ),
                  ],
                );
              },
              error: (error, stackTrace) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorStateView(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(foldersProvider),
                ),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on NavigationDrawerDestination {
  Widget _asListTile({required bool selected, required VoidCallback onTap}) {
    final label = this.label;

    return ListTile(
      selected: selected,
      leading: IconTheme(
        data: IconThemeData(
          color: selected ? const Color(0xFF153B52) : const Color(0xFF5D636B),
          size: 24,
        ),
        child: selected && selectedIcon != null ? selectedIcon! : icon,
      ),
      title: Builder(
        builder: (context) => DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: selected ? const Color(0xFF153B52) : const Color(0xFF202124),
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: .35,
          ),
          child: label,
        ),
      ),
      onTap: onTap,
      selectedTileColor: const Color(0xFFE8EFF8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      minTileHeight: 56,
      horizontalTitleGap: 18,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}

class _MailboxContent extends ConsumerWidget {
  const _MailboxContent({required this.folder, required this.searchQuery});

  final MailFolder folder;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSearching = searchQuery.isNotEmpty;
    final searchRequest = MailboxSearchRequest(
      folder: folder,
      query: searchQuery,
    );
    final messagesAsync = isSearching
        ? ref.watch(mailboxSearchProvider(searchRequest))
        : ref.watch(folderMessagesProvider(folder));

    return RefreshIndicator(
      onRefresh: () => isSearching
          ? ref.refresh(mailboxSearchProvider(searchRequest).future)
          : ref.refresh(folderMessagesProvider(folder).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
        children: [
          if (isSearching)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Search results in ${_folderLabel(folder)} for "$searchQuery"',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          messagesAsync.when(
            data: (messages) {
              if (messages.isEmpty) {
                return EmptyStateView(
                  title: isSearching ? 'No matching mail' : 'No messages yet',
                  message: isSearching
                      ? 'Try another keyword or clear the search.'
                      : 'Once ${_folderLabel(folder)} syncs, messages will appear here.',
                );
              }

              return _MessageList(messages: messages);
            },
            error: (error, stackTrace) => ErrorStateView(
              message: error.toString(),
              onRetry: () => isSearching
                  ? ref.invalidate(mailboxSearchProvider(searchRequest))
                  : ref.invalidate(folderMessagesProvider(folder)),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages});

  final List<MailMessageSummary> messages;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d');

    return Column(
      children: messages
          .map(
            (message) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                padding: const EdgeInsets.all(0),
                child: ListTile(
                  onTap: () => context.push(
                    AppRoute.messageDetail.path.replaceFirst(':id', message.id),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE8EFF8),
                    child: Text(
                      message.sender.characters.first.toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    message.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: message.isRead
                          ? FontWeight.w500
                          : FontWeight.w800,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${message.sender}\n${message.preview}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatter.format(message.receivedAt)),
                      if (message.hasAttachments)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.attach_file, size: 16),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

enum _FolderRole { inbox, sent, drafts, trash, junk, archive, custom }

List<MailFolder> _sortFolders(List<MailFolder> folders) {
  final sortedFolders = [...folders];
  sortedFolders.sort((left, right) {
    final roleComparison = _roleRank(
      _folderRole(left),
    ).compareTo(_roleRank(_folderRole(right)));
    if (roleComparison != 0) {
      return roleComparison;
    }
    return _folderLabel(
      left,
    ).toLowerCase().compareTo(_folderLabel(right).toLowerCase());
  });
  return sortedFolders;
}

String _folderLabel(MailFolder folder) =>
    folder.name.trim().isEmpty ? folder.path : folder.name;

IconData _folderIcon(MailFolder folder) {
  switch (_folderRole(folder)) {
    case _FolderRole.inbox:
      return Icons.inbox_outlined;
    case _FolderRole.sent:
      return Icons.send_outlined;
    case _FolderRole.drafts:
      return Icons.drafts_outlined;
    case _FolderRole.trash:
      return Icons.delete_outline;
    case _FolderRole.junk:
      return Icons.report_gmailerrorred_outlined;
    case _FolderRole.archive:
      return Icons.archive_outlined;
    case _FolderRole.custom:
      return Icons.folder_outlined;
  }
}

bool _isInbox(MailFolder folder) => _folderRole(folder) == _FolderRole.inbox;

_FolderRole _folderRole(MailFolder folder) {
  final normalizedPath = folder.path.trim().toLowerCase();
  final normalizedName = folder.name.trim().toLowerCase();
  if (folder.isInbox ||
      normalizedPath == 'inbox' ||
      normalizedName == 'inbox') {
    return _FolderRole.inbox;
  }
  if (normalizedPath == 'sent' || normalizedName == 'sent') {
    return _FolderRole.sent;
  }
  if (normalizedPath == 'drafts' || normalizedName == 'drafts') {
    return _FolderRole.drafts;
  }
  if (normalizedPath == 'trash' || normalizedName == 'trash') {
    return _FolderRole.trash;
  }
  if (normalizedPath == 'junk' ||
      normalizedName == 'junk' ||
      normalizedPath == 'spam' ||
      normalizedName == 'spam') {
    return _FolderRole.junk;
  }
  if (normalizedPath == 'archive' || normalizedName == 'archive') {
    return _FolderRole.archive;
  }
  return _FolderRole.custom;
}

int _roleRank(_FolderRole role) {
  switch (role) {
    case _FolderRole.inbox:
      return 0;
    case _FolderRole.sent:
      return 1;
    case _FolderRole.drafts:
      return 2;
    case _FolderRole.trash:
      return 3;
    case _FolderRole.junk:
      return 4;
    case _FolderRole.archive:
      return 5;
    case _FolderRole.custom:
      return 6;
  }
}
