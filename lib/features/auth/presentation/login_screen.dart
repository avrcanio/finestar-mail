import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route.dart';
import '../domain/finestar_mailer_preset.dart';
import 'auth_controller.dart';

const _screenBackground = Color(0xFFF7F8FC);
const _fieldStroke = Color(0xFFE8EFF8);
const _mutedText = Color(0xFF5D636B);
const _softBlue = Color(0xFFCFE7FA);

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

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final result = await ref
        .read(authControllerProvider.notifier)
        .addAccount(
          email: _emailController.text.trim(),
          displayName: _displayNameController.text.trim(),
          password: _passwordController.text,
          settings: FinestarMailerPreset.settings,
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
          settings: FinestarMailerPreset.settings,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add mailbox',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.primary,
                        fontFamily: theme.textTheme.bodyLarge?.fontFamily,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use your full email address and mailbox password. '
                      'Server settings are preconfigured.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: _mutedText,
                        fontSize: 17,
                        height: 1.45,
                        letterSpacing: .25,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _LoginCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PresetInfo(primaryColor: colorScheme.primary),
                          const SizedBox(height: 20),
                          _LoginTextField(
                            controller: _displayNameController,
                            labelText: 'Display name',
                          ),
                          _LoginTextField(
                            controller: _emailController,
                            labelText: 'Email address',
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) =>
                                (value == null || !value.contains('@'))
                                ? 'Enter a valid email address.'
                                : null,
                          ),
                          _LoginTextField(
                            controller: _passwordController,
                            labelText: 'Password',
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Password is required.'
                                : null,
                            onFieldSubmitted: (_) {
                              if (!isBusy) {
                                _submit();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy ? null : _testConnection,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              minimumSize: const Size.fromHeight(54),
                              side: BorderSide(
                                color: colorScheme.primary.withValues(
                                  alpha: .55,
                                ),
                              ),
                              shape: const StadiumBorder(),
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 15,
                                letterSpacing: .35,
                              ),
                            ),
                            child: const Text('Test connection'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isBusy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _softBlue,
                              foregroundColor: colorScheme.primary,
                              elevation: 3,
                              shadowColor: Colors.black.withValues(alpha: .12),
                              minimumSize: const Size.fromHeight(56),
                              shape: const StadiumBorder(),
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 15,
                                letterSpacing: .35,
                              ),
                            ),
                            child: Text(
                              isBusy ? 'Connecting...' : 'Add account',
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
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
        child: child,
      ),
    );
  }
}

class _PresetInfo extends StatelessWidget {
  const _PresetInfo({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.mark_email_read_outlined, color: primaryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              'Finestar mail preset',
              style: theme.textTheme.titleMedium?.copyWith(
                color: primaryColor,
                fontSize: 16,
                letterSpacing: .25,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _PresetChip(label: 'mail.finestar.hr'),
            _PresetChip(label: 'IMAP 993 SSL/TLS'),
            _PresetChip(label: 'SMTP 465 SSL/TLS'),
            _PresetChip(label: 'Full email username'),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _screenBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _fieldStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: primaryColor,
            fontSize: 12,
            letterSpacing: .25,
          ),
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.labelText,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String labelText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _fieldStroke)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textInputAction: textInputAction,
        validator: validator,
        onFieldSubmitted: onFieldSubmitted,
        cursorColor: primaryColor,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF202124),
          fontSize: 16,
          letterSpacing: .25,
        ),
        decoration: InputDecoration(
          labelText: labelText,
          floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(
            color: primaryColor,
            fontSize: 12,
            letterSpacing: .3,
          ),
          labelStyle: theme.textTheme.bodyLarge?.copyWith(
            color: _mutedText,
            fontSize: 15,
            letterSpacing: .3,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
