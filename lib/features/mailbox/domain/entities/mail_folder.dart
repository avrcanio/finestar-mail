class MailFolder {
  const MailFolder({
    required this.id,
    required this.name,
    required this.path,
    required this.isInbox,
  });

  final String id;
  final String name;
  final String path;
  final bool isInbox;
}
