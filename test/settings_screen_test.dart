import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/app/router/app_route.dart';
import 'package:finestar_mail/core/result/result.dart';
import 'package:finestar_mail/core/theme/app_theme.dart';
import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/auth/domain/repositories/auth_repository.dart';
import 'package:finestar_mail/features/settings/domain/entities/account_summary.dart';
import 'package:finestar_mail/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('settings screen shows accounts without server details', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(_FakeAuthRepository.seeded()));
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Ante Vrcan'), findsOneWidget);
    expect(find.text('avrcan@finestar.hr'), findsOneWidget);
    expect(find.text('Backup Mailbox'), findsOneWidget);
    expect(find.text('backup@finestar.hr'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Add another account'), findsOneWidget);
    expect(find.text('12 Unread'), findsOneWidget);
    expect(find.text('3 Important'), findsOneWidget);
    expect(find.text('0 Unread'), findsOneWidget);
    expect(find.text('0 Important'), findsOneWidget);

    expect(find.text('Finestar docker mailer'), findsNothing);
    expect(
      find.text('mail.finestar.hr - IMAP 993 SSL/TLS, SMTP 465 SSL/TLS'),
      findsNothing,
    );
    expect(find.textContaining('IMAP:'), findsNothing);
    expect(find.textContaining('SMTP:'), findsNothing);
  });

  testWidgets('add account actions navigate to login route', (tester) async {
    await tester.pumpWidget(_buildTestApp(_FakeAuthRepository.seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add account'));
    await tester.pumpAndSettle();

    expect(find.text('Login route reached'), findsOneWidget);
  });

  testWidgets('tapping an account sets it active', (tester) async {
    final repository = _FakeAuthRepository.seeded();
    await tester.pumpWidget(_buildTestApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Backup Mailbox'));
    await tester.pumpAndSettle();

    expect(repository.setActiveAccountCalls, 1);
    expect(repository.activeAccount?.id, 'backup@finestar.hr');
    expect(find.text('backup@finestar.hr is now active.'), findsOneWidget);
  });

  testWidgets('remove account calls auth controller flow', (tester) async {
    final repository = _FakeAuthRepository.seeded();
    await tester.pumpWidget(_buildTestApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove account').first);
    await tester.pumpAndSettle();

    expect(repository.removeAccountCalls, 1);
    expect(repository.accounts.length, 1);
  });

  testWidgets('empty settings screen shows add account state', (tester) async {
    await tester.pumpWidget(_buildTestApp(_FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);
    expect(find.byTooltip('Add account'), findsOneWidget);
    expect(find.text('Finestar docker mailer'), findsNothing);
  });
}

Widget _buildTestApp(_FakeAuthRepository repository) {
  final router = GoRouter(
    initialLocation: AppRoute.settings.path,
    routes: [
      GoRoute(
        path: AppRoute.settings.path,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoute.login.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Login route reached'))),
      ),
      GoRoute(
        path: AppRoute.inbox.path,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Inbox route reached'))),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => repository),
      accountSummariesProvider.overrideWith((ref) async {
        return const {
          'avrcan@finestar.hr': AccountSummary(
            accountEmail: 'avrcan@finestar.hr',
            displayName: 'Ante Vrcan',
            unreadCount: 12,
            importantCount: 3,
          ),
        };
      }),
    ],
    child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
}

final _settings = const ConnectionSettings(
  imapHost: 'mail.finestar.hr',
  imapPort: 993,
  imapSecurity: MailSecurity.sslTls,
  smtpHost: 'mail.finestar.hr',
  smtpPort: 465,
  smtpSecurity: MailSecurity.sslTls,
);

final _primaryAccount = MailAccount(
  id: 'avrcan@finestar.hr',
  email: 'avrcan@finestar.hr',
  displayName: 'Ante Vrcan',
  connectionSettings: _settings,
  createdAt: DateTime(2026, 4, 16),
);

final _secondaryAccount = MailAccount(
  id: 'backup@finestar.hr',
  email: 'backup@finestar.hr',
  displayName: 'Backup Mailbox',
  connectionSettings: _settings,
  createdAt: DateTime(2026, 4, 16),
);

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({List<MailAccount>? accounts, this.activeAccount})
    : accounts = [...?accounts];

  factory _FakeAuthRepository.seeded() => _FakeAuthRepository(
    accounts: [_primaryAccount, _secondaryAccount],
    activeAccount: _primaryAccount,
  );

  final List<MailAccount> accounts;
  MailAccount? activeAccount;
  int setActiveAccountCalls = 0;
  int removeAccountCalls = 0;

  @override
  Future<Result<MailAccount>> addAccount({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final account = MailAccount(
      id: email,
      email: email,
      displayName: displayName,
      connectionSettings: _settings,
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
    removeAccountCalls++;
    accounts.removeWhere((account) => account.id == accountId);
    if (activeAccount?.id == accountId) {
      activeAccount = accounts.isEmpty ? null : accounts.first;
    }
  }

  @override
  Future<void> setActiveAccount(String accountId) async {
    setActiveAccountCalls++;
    activeAccount = accounts.firstWhere((account) => account.id == accountId);
  }
}
