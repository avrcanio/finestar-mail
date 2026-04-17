import 'dart:async';

import 'package:finestar_mail/core/widgets/section_card.dart';
import 'package:finestar_mail/core/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
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
  final _selectedMessageIds = <String>{};
  final _expandedFolderPaths = <String>{};
  bool _isProcessingSelection = false;

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
        setState(() {
          _searchQuery = value.trim();
          _selectedMessageIds.clear();
        });
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelectedMessage(String messageId) {
    setState(() {
      if (!_selectedMessageIds.add(messageId)) {
        _selectedMessageIds.remove(messageId);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedMessageIds.clear);
  }

  Future<void> _deleteSelectedMessages(MailFolder folder) async {
    if (_selectedMessageIds.isEmpty ||
        _isProcessingSelection ||
        _isTrash(folder)) {
      return;
    }

    setState(() => _isProcessingSelection = true);
    final requestedIds = _selectedMessageIds.toList();
    try {
      final result = await ref
          .read(mailboxMessagesControllerProvider(folder).notifier)
          .moveSelectedToTrash(requestedIds);
      if (!mounted) {
        return;
      }
      final failedIds = result.failed
          .map((failure) => failure.messageId)
          .toSet();
      setState(() {
        _selectedMessageIds
          ..clear()
          ..addAll(failedIds);
      });
      final messenger = ScaffoldMessenger.of(context);
      if (result.movedAny && result.hasFailures) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Moved ${result.movedMessageIds.length} to Trash. '
              '${result.failed.length} failed.',
            ),
          ),
        );
      } else if (result.movedAny) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.movedMessageIds.length == 1
                  ? 'Moved message to Trash.'
                  : 'Moved ${result.movedMessageIds.length} messages to Trash.',
            ),
          ),
        );
      } else if (result.hasFailures) {
        messenger.showSnackBar(
          SnackBar(content: Text(result.failed.first.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingSelection = false);
      }
    }
  }

  Future<void> _restoreSelectedMessages(MailFolder folder) async {
    if (_selectedMessageIds.isEmpty ||
        _isProcessingSelection ||
        !_isTrash(folder)) {
      return;
    }

    setState(() => _isProcessingSelection = true);
    final requestedIds = _selectedMessageIds.toList();
    try {
      final result = await ref
          .read(mailboxMessagesControllerProvider(folder).notifier)
          .restoreSelectedToInbox(requestedIds);
      if (!mounted) {
        return;
      }
      final failedIds = result.failed
          .map((failure) => failure.messageId)
          .toSet();
      setState(() {
        _selectedMessageIds
          ..clear()
          ..addAll(failedIds);
      });
      final messenger = ScaffoldMessenger.of(context);
      if (result.restoredAny && result.hasFailures) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Restored ${result.restoredMessageIds.length} to INBOX. '
              '${result.failed.length} failed.',
            ),
          ),
        );
      } else if (result.restoredAny) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.restoredMessageIds.length == 1
                  ? 'Restored message to INBOX.'
                  : 'Restored ${result.restoredMessageIds.length} messages to INBOX.',
            ),
          ),
        );
      } else if (result.hasFailures) {
        messenger.showSnackBar(
          SnackBar(content: Text(result.failed.first.message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingSelection = false);
      }
    }
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
        expandedFolderPaths: _expandedFolderPaths,
        selectedFolder: selectedFolder,
        selectedFolderId: selectedFolder?.id,
        onFolderExpansionToggled: _toggleFolderExpansion,
        onFolderSelected: (folder) {
          _searchDebounce?.cancel();
          setState(() {
            _selectedFolderId = folder.id;
            _selectedMessageIds.clear();
          });
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
              child: _selectedMessageIds.isEmpty || selectedFolder == null
                  ? _GmailSearchBar(
                      controller: _searchController,
                      activeAccount: activeAccount,
                      isSearching: isSearching,
                      onMenuPressed: () =>
                          _scaffoldKey.currentState?.openDrawer(),
                      onChanged: _onSearchChanged,
                      onClear: _clearSearch,
                      onAvatarPressed: () =>
                          context.push(AppRoute.settings.path),
                    )
                  : _SelectionActionBar(
                      count: _selectedMessageIds.length,
                      isProcessing: _isProcessingSelection,
                      mode: _isTrash(selectedFolder)
                          ? _SelectionActionMode.restore
                          : _SelectionActionMode.delete,
                      onClose: _clearSelection,
                      onAction: () => _isTrash(selectedFolder)
                          ? _restoreSelectedMessages(selectedFolder)
                          : _deleteSelectedMessages(selectedFolder),
                    ),
            ),
            Expanded(
              child: selectedFolder == null
                  ? const Center(child: CircularProgressIndicator())
                  : _MailboxContent(
                      folder: selectedFolder,
                      searchQuery: _searchQuery,
                      selectedMessageIds: _selectedMessageIds,
                      onToggleSelected: _toggleSelectedMessage,
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

  void _toggleFolderExpansion(String path) {
    setState(() {
      if (!_expandedFolderPaths.add(path)) {
        _expandedFolderPaths.remove(path);
      }
    });
  }
}

enum _SelectionActionMode { delete, restore }

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.isProcessing,
    required this.mode,
    required this.onClose,
    required this.onAction,
  });

  final int count;
  final bool isProcessing;
  final _SelectionActionMode mode;
  final VoidCallback onClose;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
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
              tooltip: 'Clear selection',
              onPressed: isProcessing ? null : onClose,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text(
                '$count selected',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isProcessing)
              const Padding(
                padding: EdgeInsets.only(right: 18),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            else
              IconButton(
                tooltip: mode == _SelectionActionMode.restore
                    ? 'Restore selected to INBOX'
                    : 'Move selected to Trash',
                onPressed: onAction,
                icon: Icon(
                  mode == _SelectionActionMode.restore
                      ? Icons.restore_from_trash_outlined
                      : Icons.delete_outline,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
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
              child: Tooltip(
                message: 'Manage account',
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
    required this.expandedFolderPaths,
    required this.selectedFolder,
    required this.selectedFolderId,
    required this.onFolderExpansionToggled,
    required this.onFolderSelected,
  });

  final Set<String> expandedFolderPaths;
  final MailFolder? selectedFolder;
  final String? selectedFolderId;
  final ValueChanged<String> onFolderExpansionToggled;
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
                final tree = _buildFolderTree(folders);
                if (tree.isEmpty) {
                  return const ListTile(
                    leading: Icon(Icons.folder_off_outlined),
                    title: Text('No folders found'),
                  );
                }

                final effectiveExpandedPaths = {
                  ...expandedFolderPaths,
                  ..._selectedAncestorPaths(selectedFolder),
                };
                return Column(
                  children: [
                    for (final node in tree)
                      ..._buildFolderRows(
                        context: context,
                        node: node,
                        depth: 0,
                        expandedPaths: effectiveExpandedPaths,
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

  List<Widget> _buildFolderRows({
    required BuildContext context,
    required _FolderTreeNode node,
    required int depth,
    required Set<String> expandedPaths,
  }) {
    final expanded = expandedPaths.contains(node.path);
    return [
      _FolderDrawerTile(
        node: node,
        depth: depth,
        selected: _isSelected(node.folder),
        expanded: expanded,
        onExpandTap: node.children.isNotEmpty
            ? () => onFolderExpansionToggled(node.path)
            : null,
        onOpenTap: node.folder != null && node.folder!.selectable
            ? () => onFolderSelected(node.folder!)
            : node.children.isNotEmpty
            ? () => onFolderExpansionToggled(node.path)
            : null,
      ),
      if (expanded)
        for (final child in node.children)
          ..._buildFolderRows(
            context: context,
            node: child,
            depth: depth + 1,
            expandedPaths: expandedPaths,
          ),
    ];
  }

  bool _isSelected(MailFolder? folder) {
    if (folder == null) {
      return false;
    }
    return selectedFolderId == folder.id ||
        (selectedFolderId == null && _isInbox(folder));
  }
}

class _FolderDrawerTile extends StatelessWidget {
  const _FolderDrawerTile({
    required this.node,
    required this.depth,
    required this.selected,
    required this.expanded,
    required this.onExpandTap,
    required this.onOpenTap,
  });

  final _FolderTreeNode node;
  final int depth;
  final bool selected;
  final bool expanded;
  final VoidCallback? onExpandTap;
  final VoidCallback? onOpenTap;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final primaryColor = selected
        ? const Color(0xFF153B52)
        : const Color(0xFF202124);
    return ListTile(
      selected: selected,
      enabled: onOpenTap != null,
      leading: Icon(
        hasChildren
            ? (expanded ? Icons.folder_open_outlined : Icons.folder_outlined)
            : _folderIcon(node.folder!),
        color: selected ? const Color(0xFF153B52) : const Color(0xFF5D636B),
        size: 24,
      ),
      title: Text(
        node.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: primaryColor,
          fontSize: 16,
          fontWeight: selected || hasChildren
              ? FontWeight.w700
              : FontWeight.w500,
          letterSpacing: .35,
        ),
      ),
      trailing: hasChildren
          ? IconButton(
              tooltip: expanded ? 'Collapse folder' : 'Expand folder',
              onPressed: onExpandTap,
              icon: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: const Color(0xFF5D636B),
              ),
            )
          : null,
      onTap: onOpenTap,
      selectedTileColor: const Color(0xFFE8EFF8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      minTileHeight: 56,
      horizontalTitleGap: 18,
      contentPadding: EdgeInsets.only(left: 24 + depth * 22, right: 24),
    );
  }
}

class _FolderTreeNode {
  _FolderTreeNode({required this.path, required this.label, this.folder});

  final String path;
  final String label;
  MailFolder? folder;
  final children = <_FolderTreeNode>[];
}

List<_FolderTreeNode> _buildFolderTree(List<MailFolder> folders) {
  final byPath = <String, _FolderTreeNode>{};
  final roots = <_FolderTreeNode>[];

  _FolderTreeNode ensureNode(String path, {MailFolder? folder}) {
    final existing = byPath[path];
    if (existing != null) {
      if (folder != null) {
        existing.folder = folder;
      }
      return existing;
    }
    final node = _FolderTreeNode(
      path: path,
      label: folder == null ? _pathLabel(path) : _folderLabel(folder),
      folder: folder,
    );
    byPath[path] = node;
    return node;
  }

  for (final folder in folders) {
    ensureNode(folder.path, folder: folder);
  }

  for (final folder in folders) {
    final parentPath = _folderParentPath(folder);
    if (parentPath == null) {
      continue;
    }
    ensureNode(parentPath);
  }

  final nodes = byPath.values.toList();
  for (final node in nodes) {
    final parentPath = node.folder == null
        ? _pathParentPath(node.path)
        : _folderParentPath(node.folder!);
    final parent = parentPath == null ? null : byPath[parentPath];
    if (parent == null || parent == node) {
      roots.add(node);
    } else if (!parent.children.contains(node)) {
      parent.children.add(node);
    }
  }

  void sortNodes(List<_FolderTreeNode> nodes) {
    nodes.sort(_compareFolderNodes);
    for (final node in nodes) {
      sortNodes(node.children);
    }
  }

  sortNodes(roots);
  return roots;
}

int _compareFolderNodes(_FolderTreeNode left, _FolderTreeNode right) {
  final leftRole = left.folder == null
      ? _FolderRole.custom
      : _folderRole(left.folder!);
  final rightRole = right.folder == null
      ? _FolderRole.custom
      : _folderRole(right.folder!);
  final roleComparison = _roleRank(leftRole).compareTo(_roleRank(rightRole));
  if (roleComparison != 0) {
    return roleComparison;
  }
  return left.label.toLowerCase().compareTo(right.label.toLowerCase());
}

Set<String> _selectedAncestorPaths(MailFolder? selectedFolder) {
  if (selectedFolder == null) {
    return const {};
  }
  final ancestors = <String>{};
  var parentPath = _folderParentPath(selectedFolder);
  while (parentPath != null && ancestors.add(parentPath)) {
    parentPath = _pathParentPath(parentPath);
  }
  return ancestors;
}

String? _folderParentPath(MailFolder folder) {
  final parentPath = folder.parentPath?.trim();
  if (parentPath != null && parentPath.isNotEmpty) {
    return parentPath;
  }
  return _pathParentPath(folder.path);
}

String? _pathParentPath(String path) {
  final separator = _folderSeparator(path);
  if (separator == null) {
    return null;
  }
  final index = path.lastIndexOf(separator);
  if (index <= 0) {
    return null;
  }
  return path.substring(0, index);
}

String? _folderSeparator(String path) {
  if (path.contains('/')) {
    return '/';
  }
  if (path.contains('.')) {
    return '.';
  }
  return null;
}

String _pathLabel(String path) {
  final separator = _folderSeparator(path);
  if (separator == null) {
    return path;
  }
  final segments = path
      .split(separator)
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  return segments.isEmpty ? path : segments.last;
}

String _folderLabel(MailFolder folder) {
  if (_isInbox(folder)) {
    return 'Inbox';
  }
  final displayName = folder.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  if (folder.depth != null && folder.depth! > 0) {
    return _pathLabel(folder.path);
  }
  final parentPath = folder.parentPath?.trim();
  if (parentPath != null && parentPath.isNotEmpty) {
    return _pathLabel(folder.path);
  }
  if (_folderParentPath(folder) != null) {
    return _pathLabel(folder.path);
  }
  return folder.name.trim().isEmpty ? folder.path : folder.name;
}

class _MailboxContent extends ConsumerStatefulWidget {
  const _MailboxContent({
    required this.folder,
    required this.searchQuery,
    required this.selectedMessageIds,
    required this.onToggleSelected,
  });

  final MailFolder folder;
  final String searchQuery;
  final Set<String> selectedMessageIds;
  final ValueChanged<String> onToggleSelected;

  @override
  ConsumerState<_MailboxContent> createState() => _MailboxContentState();
}

class _MailboxContentState extends ConsumerState<_MailboxContent> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (widget.searchQuery.isNotEmpty || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter > 600) {
      return;
    }
    ref
        .read(mailboxMessagesControllerProvider(widget.folder).notifier)
        .loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final searchQuery = widget.searchQuery;
    final isSearching = searchQuery.isNotEmpty;
    final searchRequest = MailboxSearchRequest(
      folder: folder,
      query: searchQuery,
    );
    final searchAsync = isSearching
        ? ref.watch(mailboxSearchProvider(searchRequest))
        : null;
    final pagedAsync = isSearching
        ? null
        : ref.watch(mailboxMessagesControllerProvider(folder));

    return RefreshIndicator(
      onRefresh: () => isSearching
          ? ref.refresh(mailboxSearchProvider(searchRequest).future)
          : ref
                .read(mailboxMessagesControllerProvider(folder).notifier)
                .refresh(),
      child: ListView(
        controller: _scrollController,
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
          (isSearching ? searchAsync! : pagedAsync!).when(
            data: (messages) {
              final visibleMessages = isSearching
                  ? messages as List<MailMessageSummary>
                  : (messages as MailboxMessagesState).messages;
              if (visibleMessages.isEmpty) {
                return EmptyStateView(
                  title: isSearching ? 'No matching mail' : 'No messages yet',
                  message: isSearching
                      ? 'Try another keyword or clear the search.'
                      : 'Once ${_folderLabel(folder)} syncs, messages will appear here.',
                );
              }

              return Column(
                children: [
                  _MessageList(
                    messages: visibleMessages,
                    folder: folder,
                    selectedMessageIds: widget.selectedMessageIds,
                    selectionEnabled: !isSearching,
                    onToggleSelected: widget.onToggleSelected,
                  ),
                  if (!isSearching)
                    _LoadMoreFooter(
                      state: messages as MailboxMessagesState,
                      onRetry: () => ref
                          .read(
                            mailboxMessagesControllerProvider(folder).notifier,
                          )
                          .loadMore(),
                    ),
                ],
              );
            },
            error: (error, stackTrace) => ErrorStateView(
              message: error.toString(),
              onRetry: () => isSearching
                  ? ref.invalidate(mailboxSearchProvider(searchRequest))
                  : ref.invalidate(mailboxMessagesControllerProvider(folder)),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.state, required this.onRetry});

  final MailboxMessagesState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final error = state.loadMoreError;
    if (error == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            'Couldn\'t load older mail',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.folder,
    required this.selectedMessageIds,
    required this.selectionEnabled,
    required this.onToggleSelected,
  });

  final List<MailMessageSummary> messages;
  final MailFolder folder;
  final Set<String> selectedMessageIds;
  final bool selectionEnabled;
  final ValueChanged<String> onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = DateFormat('MMM d');

    return Column(
      children: messages.map((message) {
        final selected = selectedMessageIds.contains(message.id);
        final selectionActive = selectedMessageIds.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SectionCard(
            color: selected
                ? const Color(0xFFD7EAFE)
                : message.isRead
                ? Colors.white
                : const Color(0xFFEAF4FF),
            padding: const EdgeInsets.all(0),
            child: ListTile(
              onLongPress: () => _showMessageActions(
                context: context,
                ref: ref,
                message: message,
              ),
              onTap: selectionActive && selectionEnabled
                  ? () => onToggleSelected(message.id)
                  : () => context.push(
                      AppRoute.messageDetail.path.replaceFirst(
                        ':id',
                        message.id,
                      ),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: Tooltip(
                message: 'Select message',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: selectionEnabled
                      ? () => onToggleSelected(message.id)
                      : null,
                  child: CircleAvatar(
                    backgroundColor: selected
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFFE8EFF8),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : Text(
                            message.sender.characters.first.toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isImportant)
                        const Icon(
                          Icons.error,
                          size: 16,
                          color: Color(0xFFD93025),
                        ),
                      if (message.isPinned)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 16,
                            color: Color(0xFF153B52),
                          ),
                        ),
                      if (message.hasAttachments)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.attach_file, size: 16),
                        ),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _showMessageActions({
    required BuildContext context,
    required WidgetRef ref,
    required MailMessageSummary message,
  }) async {
    final account = ref.read(activeAccountProvider).asData?.value;
    if (account == null) {
      return;
    }

    Future<void> apply(Future<void> Function() action) async {
      Navigator.of(context).pop();
      await action();
      ref.invalidate(mailboxMessagesControllerProvider(folder));
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  message.isRead
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                ),
                title: Text(message.isRead ? 'Mark as unread' : 'Mark as read'),
                onTap: () => apply(
                  () => ref
                      .read(mailboxRepositoryProvider)
                      .setMessageRead(
                        accountId: account.id,
                        messageId: message.id,
                        isRead: !message.isRead,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  message.isImportant ? 'Remove important' : 'Mark important',
                ),
                onTap: () => apply(
                  () => ref
                      .read(mailboxRepositoryProvider)
                      .setMessageImportant(
                        accountId: account.id,
                        messageId: message.id,
                        isImportant: !message.isImportant,
                      ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(message.isPinned ? 'Unpin' : 'Pin to top'),
                onTap: () => apply(
                  () => ref
                      .read(mailboxRepositoryProvider)
                      .setMessagePinned(
                        accountId: account.id,
                        messageId: message.id,
                        isPinned: !message.isPinned,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _FolderRole { inbox, sent, drafts, trash, junk, archive, custom }

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

bool _isTrash(MailFolder folder) => _folderRole(folder) == _FolderRole.trash;

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
