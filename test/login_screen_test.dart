import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/core/theme/app_theme.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/domain/repositories/auth_repository.dart';
import 'package:finestar_mail/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('login screen uses main-screen style content', (tester) async {
    await tester.pumpWidget(_buildTestApp(_FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Add mailbox'), findsOneWidget);
    expect(find.text('Finestar mail preset'), findsNothing);
    expect(find.text('mail.finestar.hr'), findsNothing);
    expect(find.text('IMAP 993 SSL/TLS'), findsNothing);
    expect(find.text('SMTP 465 SSL/TLS'), findsNothing);
    expect(find.text('Full email username'), findsNothing);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Test connection'), findsNothing);
    expect(find.text('Add account'), findsOneWidget);
  });

  testWidgets('login screen keeps validation behavior', (tester) async {
    await tester.pumpWidget(_buildTestApp(_FakeAuthRepository()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('add account still navigates to inbox on success', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_buildTestApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'App Test 2');
    await tester.enterText(find.byType(TextFormField).at(1), _account.email);
    await tester.enterText(find.byType(TextFormField).at(2), 'secret');
    await tester.ensureVisible(find.text('Add account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();

    expect(repository.addAccountCalls, 1);
    expect(find.text('Inbox reached'), findsOneWidget);
  });
}

Widget _buildTestApp(_FakeAuthRepository repository) {
  final router = GoRouter(
    initialLocation: AppRoute.login.path,
    routes: [
      GoRoute(
        path: AppRoute.login.path,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.inbox.path,
        builder: (context, state) =>
            const Scaffold(body: Text('Inbox reached')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWith((ref) => repository)],
    child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
}

final _account = MailAccount(
  id: 'app-test-2@finestar.hr',
  email: 'app-test-2@finestar.hr',
  displayName: 'App Test 2',
  connectionSettings: const ConnectionSettings(
    imapHost: 'mail.finestar.hr',
    imapPort: 993,
    imapSecurity: MailSecurity.sslTls,
    smtpHost: 'mail.finestar.hr',
    smtpPort: 465,
    smtpSecurity: MailSecurity.sslTls,
  ),
  createdAt: DateTime(2026, 4, 16),
);

class _FakeAuthRepository implements AuthRepository {
  int addAccountCalls = 0;
  MailAccount? activeAccount;
  final List<MailAccount> accounts = [];

  @override
  Future<Result<MailAccount>> addAccount({
    required String email,
    required String displayName,
    required String password,
  }) async {
    addAccountCalls++;
    final account = MailAccount(
      id: email,
      email: email,
      displayName: displayName,
      connectionSettings: _account.connectionSettings,
      createdAt: DateTime(2026, 4, 16),
    );
    accounts.add(account);
    activeAccount = account;
    return Success(account);
  }

  @override
  Future<MailAccount?> getActiveAccount() async => activeAccount;

  @override
  Future<List<MailAccount>> getAccounts() async => accounts;

  @override
  Future<void> removeAccount(String accountId) async {
    accounts.removeWhere((account) => account.id == accountId);
    if (activeAccount?.id == accountId) {
      activeAccount = accounts.isEmpty ? null : accounts.first;
    }
  }

  @override
  Future<void> setActiveAccount(String accountId) async {
    activeAccount = accounts.where((account) => account.id == accountId).first;
  }
}
