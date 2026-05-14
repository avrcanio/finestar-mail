/// Thrown when the server reports the message no longer exists at the stored folder/UID
/// (e.g. moved or deleted in Thunderbird). Local cache rows should already be removed.
class StaleMailboxMessageException implements Exception {
  const StaleMailboxMessageException();

  @override
  String toString() =>
      'This message was removed or moved in another email app. Your inbox was refreshed.';
}
