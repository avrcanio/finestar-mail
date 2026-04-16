import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/result/result.dart';
import '../domain/entities/connection_settings.dart';
import '../domain/entities/mail_account.dart';

final currentAccountProvider = FutureProvider<MailAccount?>((ref) {
  return ref.watch(authRepositoryProvider).getSignedInAccount();
});

final authControllerProvider =
    AsyncNotifierProvider.autoDispose<AuthController, MailAccount?>(
      AuthController.new,
    );

class AuthController extends AsyncNotifier<MailAccount?> {
  @override
  Future<MailAccount?> build() async {
    return ref.watch(authRepositoryProvider).getSignedInAccount();
  }

  Future<Result<void>> testConnection({
    required String email,
    required String password,
    required ConnectionSettings settings,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .watch(authRepositoryProvider)
        .testConnection(email: email, password: password, settings: settings);
    state = AsyncData(state.asData?.value);
    return result;
  }

  Future<Result<MailAccount>> signIn({
    required String email,
    required String displayName,
    required String password,
    required ConnectionSettings settings,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .watch(authRepositoryProvider)
        .signIn(
          email: email,
          displayName: displayName,
          password: password,
          settings: settings,
        );

    result.when(
      success: (account) => state = AsyncData(account),
      failure: (message) => state = AsyncError(message, StackTrace.current),
    );

    return result;
  }

  Future<void> signOut() async {
    await ref.watch(authRepositoryProvider).signOut();
    state = const AsyncData(null);
    ref.invalidate(currentAccountProvider);
  }
}
