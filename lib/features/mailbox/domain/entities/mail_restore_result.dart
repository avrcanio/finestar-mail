class MailRestoreResult {
  const MailRestoreResult({
    required this.restoredMessageIds,
    required this.failed,
  });

  final List<String> restoredMessageIds;
  final List<MailRestoreFailure> failed;

  bool get hasFailures => failed.isNotEmpty;
  bool get restoredAny => restoredMessageIds.isNotEmpty;
}

class MailRestoreFailure {
  const MailRestoreFailure({required this.messageId, required this.message});

  final String messageId;
  final String message;
}
