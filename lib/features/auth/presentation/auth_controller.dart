import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/result.dart';
import '../domain/entities/connection_settings.dart';
import '../domain/entities/mail_account.dart';

final accountsProvider = FutureProvider<List<MailAccount>>((ref) {
  return ref.watch(authRepositoryProvider).getAccounts();
});

final activeAccountProvider = FutureProvider<MailAccount?>((ref) {
  return ref.watch(authRepositoryProvider).getActiveAccount();
});

final authControllerProvider =
    AsyncNotifierProvider.autoDispose<AuthController, MailAccount?>(
      AuthController.new,
    );

class AuthController extends AsyncNotifier<MailAccount?> {
  @override
  Future<MailAccount?> build() async {
    return ref.read(authRepositoryProvider).getActiveAccount();
  }

  Future<Result<void>> testConnection({
    required String email,
    required String password,
    required ConnectionSettings settings,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(authRepositoryProvider)
        .testConnection(email: email, password: password, settings: settings);
    if (!ref.mounted) {
      return result;
    }
    state = AsyncData(state.asData?.value);
    return result;
  }

  Future<Result<MailAccount>> addAccount({
    required String email,
    required String displayName,
    required String password,
    required ConnectionSettings settings,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(authRepositoryProvider)
        .addAccount(
          email: email,
          displayName: displayName,
          password: password,
          settings: settings,
        );

    if (!ref.mounted) {
      return result;
    }

    result.when(
      success: (account) {
        ref.invalidate(accountsProvider);
        ref.invalidate(activeAccountProvider);
        state = AsyncData(account);
      },
      failure: (message) => state = AsyncError(message, StackTrace.current),
    );

    return result;
  }

  Future<void> setActiveAccount(String accountId) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.setActiveAccount(accountId);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(await repository.getActiveAccount());
  }

  Future<void> removeAccount(String accountId) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.removeAccount(accountId);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(await repository.getActiveAccount());
  }
}
