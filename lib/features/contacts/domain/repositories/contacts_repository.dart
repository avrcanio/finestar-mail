import '../entities/contact_suggestion.dart';

abstract class ContactsRepository {
  Future<List<ContactSuggestion>> suggestContacts(String query);
}
