class AccountSummary {
  const AccountSummary({
    required this.accountEmail,
    required this.displayName,
    required this.unreadCount,
    required this.importantCount,
  });

  final String accountEmail;
  final String displayName;
  final int unreadCount;
  final int importantCount;
}
