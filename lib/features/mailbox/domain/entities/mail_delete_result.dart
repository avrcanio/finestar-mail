class MailDeleteResult {
  const MailDeleteResult({required this.movedMessageIds, required this.failed});

  final List<String> movedMessageIds;
  final List<MailDeleteFailure> failed;

  bool get hasFailures => failed.isNotEmpty;
  bool get movedAny => movedMessageIds.isNotEmpty;
}

class MailDeleteFailure {
  const MailDeleteFailure({required this.messageId, required this.message});

  final String messageId;
  final String message;
}
