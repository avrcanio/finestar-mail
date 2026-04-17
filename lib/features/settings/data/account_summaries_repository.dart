import 'package:logger/logger.dart';

import '../../../data/remote/backend_mail_api_client.dart';
import '../../auth/data/backend_auth_token_selector.dart';
import '../domain/entities/account_summary.dart';

typedef AccountSummariesFcmTokenLoader = Future<String?> Function();

class AccountSummariesRepository {
  const AccountSummariesRepository({
    required BackendMailApiClient backendMailApiClient,
    required BackendAuthTokenSelector backendAuthTokenSelector,
    required AccountSummariesFcmTokenLoader fcmTokenLoader,
    Logger? logger,
  }) : _backendMailApiClient = backendMailApiClient,
       _backendAuthTokenSelector = backendAuthTokenSelector,
       _fcmTokenLoader = fcmTokenLoader,
       _logger = logger;

  final BackendMailApiClient _backendMailApiClient;
  final BackendAuthTokenSelector _backendAuthTokenSelector;
  final AccountSummariesFcmTokenLoader _fcmTokenLoader;
  final Logger? _logger;

  Future<Map<String, AccountSummary>> fetchSummariesByEmail() async {
    try {
      final fcmToken = (await _fcmTokenLoader())?.trim();
      if (fcmToken == null || fcmToken.isEmpty) {
        return const {};
      }

      final selectedToken = await _backendAuthTokenSelector.selectToken();
      if (selectedToken == null) {
        return const {};
      }

      final response = await _backendMailApiClient.accountSummaries(
        token: selectedToken.token,
        fcmToken: fcmToken,
      );

      return {
        for (final summary in response.accounts)
          if (summary.accountEmail.trim().isNotEmpty)
            summary.accountEmail.trim().toLowerCase(): AccountSummary(
              accountEmail: summary.accountEmail,
              displayName: summary.displayName,
              unreadCount: summary.unreadCount,
              importantCount: summary.importantCount,
            ),
      };
    } catch (error, stackTrace) {
      _logger?.w(
        'Account summaries fetch failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return const {};
    }
  }
}
