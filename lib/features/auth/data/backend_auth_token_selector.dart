import '../../../data/secure/secure_storage_service.dart';
import '../domain/entities/mail_account.dart';
import '../domain/repositories/auth_repository.dart';

class SelectedBackendAuthToken {
  const SelectedBackendAuthToken({required this.account, required this.token});

  final MailAccount account;
  final String token;
}

class BackendAuthTokenSelector {
  const BackendAuthTokenSelector({
    required AuthRepository authRepository,
    required SecureStorageService secureStorageService,
  }) : _authRepository = authRepository,
       _secureStorageService = secureStorageService;

  final AuthRepository _authRepository;
  final SecureStorageService _secureStorageService;

  Future<SelectedBackendAuthToken?> selectToken() async {
    final accounts = await _authRepository.getAccounts();
    if (accounts.isEmpty) {
      return null;
    }

    final activeAccountId = await _secureStorageService.readActiveAccountId();
    if (activeAccountId != null && activeAccountId.trim().isNotEmpty) {
      final activeAccount = _firstAccountById(accounts, activeAccountId);
      final activeToken = activeAccount == null
          ? null
          : await _tokenFor(activeAccount.id);
      if (activeAccount != null && activeToken != null) {
        return SelectedBackendAuthToken(
          account: activeAccount,
          token: activeToken,
        );
      }
    }

    for (final account in accounts) {
      final token = await _tokenFor(account.id);
      if (token != null) {
        return SelectedBackendAuthToken(account: account, token: token);
      }
    }

    return null;
  }

  MailAccount? _firstAccountById(List<MailAccount> accounts, String accountId) {
    final normalizedId = accountId.trim().toLowerCase();
    for (final account in accounts) {
      if (account.id.toLowerCase() == normalizedId) {
        return account;
      }
    }
    return null;
  }

  Future<String?> _tokenFor(String accountId) async {
    final token = await _secureStorageService.readAuthToken(accountId);
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
