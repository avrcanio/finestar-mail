class MailFolder {
  const MailFolder({
    required this.id,
    required this.name,
    required this.path,
    required this.isInbox,
    this.displayName,
    this.parentPath,
    this.depth,
    this.selectable = true,
  });

  final String id;
  final String name;
  final String path;
  final bool isInbox;
  final String? displayName;
  final String? parentPath;
  final int? depth;
  final bool selectable;
}
