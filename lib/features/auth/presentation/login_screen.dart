import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/app_route.dart';
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
  var _isRegisteringDevice = false;

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

    setState(() => _isRegisteringDevice = true);
    final result = await ref
        .read(authControllerProvider.notifier)
        .addAccount(
          email: _emailController.text.trim(),
          displayName: _displayNameController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) {
      return;
    }

    await result.when(
      success: (account) async {
        final registered = await ref
            .read(deviceRegistrationServiceProvider)
            .registerAccount(account);

        if (!mounted) {
          return;
        }

        _showSnackBar(
          registered
              ? 'Push notifications enabled for this mailbox.'
              : 'Mailbox added, but push notification setup did not complete.',
        );
        context.go(AppRoute.inbox.path);
      },
      failure: (message) async {
        _showSnackBar(message);
      },
    );

    if (mounted) {
      setState(() => _isRegisteringDevice = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.isLoading || _isRegisteringDevice;
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
                      'Use your full email address and mailbox password.',
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
                    ElevatedButton(
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
                        _isRegisteringDevice
                            ? 'Setting up...'
                            : isBusy
                            ? 'Connecting...'
                            : 'Add account',
                      ),
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

class _LoginTextField extends StatefulWidget {
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
  State<_LoginTextField> createState() => _LoginTextFieldState();
}

class _LoginTextFieldState extends State<_LoginTextField> {
  var _isPasswordVisible = false;

  @override
  void didUpdateWidget(covariant _LoginTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.obscureText && _isPasswordVisible) {
      _hidePassword();
    }
  }

  void _showPassword() {
    if (!_isPasswordVisible) {
      setState(() => _isPasswordVisible = true);
    }
  }

  void _hidePassword() {
    if (_isPasswordVisible) {
      setState(() => _isPasswordVisible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final effectiveObscureText = widget.obscureText && !_isPasswordVisible;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _fieldStroke)),
      ),
      child: TextFormField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: effectiveObscureText,
        textInputAction: widget.textInputAction,
        validator: widget.validator,
        onFieldSubmitted: widget.onFieldSubmitted,
        cursorColor: primaryColor,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF202124),
          fontSize: 16,
          letterSpacing: .25,
        ),
        decoration: InputDecoration(
          labelText: widget.labelText,
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
          suffixIcon: widget.obscureText
              ? _PasswordVisibilityHoldIcon(
                  visible: _isPasswordVisible,
                  onPressStart: _showPassword,
                  onPressEnd: _hidePassword,
                )
              : null,
        ),
      ),
    );
  }
}

class _PasswordVisibilityHoldIcon extends StatelessWidget {
  const _PasswordVisibilityHoldIcon({
    required this.visible,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final bool visible;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onPressStart(),
      onPointerUp: (_) => onPressEnd(),
      onPointerCancel: (_) => onPressEnd(),
      child: Tooltip(
        message: 'Hold to show password',
        child: Semantics(
          label: 'Hold to show password',
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _mutedText,
            ),
          ),
        ),
      ),
    );
  }
}
