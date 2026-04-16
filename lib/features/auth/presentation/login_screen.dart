import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:finestar_mail/core/constants/app_strings.dart';
import 'package:finestar_mail/core/widgets/section_card.dart';

import '../../../app/router/app_route.dart';
import '../domain/entities/connection_settings.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _imapHostController = TextEditingController();
  final _imapPortController = TextEditingController(text: '993');
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController(text: '465');

  MailSecurity _imapSecurity = MailSecurity.sslTls;
  MailSecurity _smtpSecurity = MailSecurity.sslTls;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _imapHostController.dispose();
    _imapPortController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    super.dispose();
  }

  ConnectionSettings get _settings => ConnectionSettings(
    imapHost: _imapHostController.text.trim(),
    imapPort: int.tryParse(_imapPortController.text) ?? 0,
    imapSecurity: _imapSecurity,
    smtpHost: _smtpHostController.text.trim(),
    smtpPort: int.tryParse(_smtpPortController.text) ?? 0,
    smtpSecurity: _smtpSecurity,
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final result = await ref
        .read(authControllerProvider.notifier)
        .signIn(
          email: _emailController.text.trim(),
          displayName: _displayNameController.text.trim(),
          password: _passwordController.text,
          settings: _settings,
        );

    if (!mounted) {
      return;
    }

    result.when(
      success: (_) => context.go(AppRoute.inbox.path),
      failure: _showSnackBar,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final result = await ref
        .read(authControllerProvider.notifier)
        .testConnection(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          settings: _settings,
        );

    if (!mounted) {
      return;
    }

    result.when(
      success: (_) => _showSnackBar('Connection settings look valid.'),
      failure: _showSnackBar,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.isLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8EFE4), Color(0xFFF3D7BF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.loginTitle,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.loginSubtitle,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      SectionCard(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _displayNameController,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                              ),
                              validator: (value) =>
                                  (value == null || !value.contains('@'))
                                  ? 'Enter a valid email address.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                  ? 'Password is required.'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SectionCard(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _imapHostController,
                              decoration: const InputDecoration(
                                labelText: 'IMAP host',
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                  ? 'IMAP host is required.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _imapPortController,
                                    decoration: const InputDecoration(
                                      labelText: 'IMAP port',
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<MailSecurity>(
                                    initialValue: _imapSecurity,
                                    decoration: const InputDecoration(
                                      labelText: 'IMAP security',
                                    ),
                                    items: MailSecurity.values
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Text(value.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _imapSecurity = value);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _smtpHostController,
                              decoration: const InputDecoration(
                                labelText: 'SMTP host',
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                  ? 'SMTP host is required.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _smtpPortController,
                                    decoration: const InputDecoration(
                                      labelText: 'SMTP port',
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<MailSecurity>(
                                    initialValue: _smtpSecurity,
                                    decoration: const InputDecoration(
                                      labelText: 'SMTP security',
                                    ),
                                    items: MailSecurity.values
                                        .map(
                                          (value) => DropdownMenuItem(
                                            value: value,
                                            child: Text(value.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _smtpSecurity = value);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isBusy ? null : _testConnection,
                              child: const Text('Test connection'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isBusy ? null : _submit,
                              child: Text(
                                isBusy ? 'Connecting...' : 'Save and continue',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
