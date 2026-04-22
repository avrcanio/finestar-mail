import 'package:logger/logger.dart';

import '../../../data/remote/backend_mail_api_client.dart';
import '../../auth/data/backend_auth_token_selector.dart';
import '../domain/entities/contact_suggestion.dart';
import '../domain/repositories/contacts_repository.dart';

class ContactsRepositoryImpl implements ContactsRepository {
  const ContactsRepositoryImpl({
    required BackendMailApiClient backendMailApiClient,
    required BackendAuthTokenSelector backendAuthTokenSelector,
    Logger? logger,
  }) : _backendMailApiClient = backendMailApiClient,
       _backendAuthTokenSelector = backendAuthTokenSelector,
       _logger = logger;

  final BackendMailApiClient _backendMailApiClient;
  final BackendAuthTokenSelector _backendAuthTokenSelector;
  final Logger? _logger;

  @override
  Future<List<ContactSuggestion>> suggestContacts(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) {
      return const [];
    }

    try {
      final selectedToken = await _backendAuthTokenSelector.selectToken();
      if (selectedToken == null) {
        return const [];
      }

      final response = await _backendMailApiClient.contactSuggestions(
        token: selectedToken.token,
        query: trimmedQuery,
      );
      return response.contacts
          .where((contact) => contact.email.trim().isNotEmpty)
          .map(
            (contact) => ContactSuggestion(
              id: contact.id,
              email: contact.email,
              displayName: contact.displayName,
              source: contact.source,
              timesContacted: contact.timesContacted,
              lastUsedAt: contact.lastUsedAt,
              createdAt: contact.createdAt,
              updatedAt: contact.updatedAt,
            ),
          )
          .toList();
    } catch (error, stackTrace) {
      _logger?.w(
        'Contact suggestions fetch failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }
}
