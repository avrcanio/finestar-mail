import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../auth/domain/entities/mail_account.dart';

const _pushApiBaseUrl = String.fromEnvironment(
  'PUSH_API_BASE_URL',
  defaultValue: 'https://mailadmin.finestar.hr',
);
const _deviceRegistrationSecret = String.fromEnvironment(
  'FCM_REGISTRATION_SECRET',
);

class PushNotificationService {
  PushNotificationService({
    required Logger logger,
    void Function(PushRegistrationStatus status)? onStatusChanged,
  }) : _logger = logger,
       _onStatusChanged = onStatusChanged;

  final Logger _logger;
  final void Function(PushRegistrationStatus status)? _onStatusChanged;
  StreamSubscription<String>? _tokenRefreshSubscription;
  MailAccount? _registeredAccount;

  bool get isConfigured => _deviceRegistrationSecret.isNotEmpty;

  Future<void> registerAccount(MailAccount account) async {
    _registeredAccount = account;
    _setStatus(PushRegistrationStatus.registering(account.email));

    if (!isConfigured) {
      const message = 'FCM_REGISTRATION_SECRET is empty.';
      _setStatus(PushRegistrationStatus.skipped(message));
      _logger.w('FCM registration skipped: $message');
      return;
    }

    try {
      await _requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        const message = 'Firebase returned no token.';
        _setStatus(PushRegistrationStatus.skipped(message));
        _logger.w('FCM registration skipped: $message');
        return;
      }

      await _registerToken(account: account, token: token);
      _listenForTokenRefresh();
    } catch (error, stackTrace) {
      _logger.e(
        'FCM registration failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _setStatus(PushRegistrationStatus.failure(error.toString()));
    }
  }

  Future<RemoteMessage?> takeInitialMessage() {
    return FirebaseMessaging.instance.getInitialMessage();
  }

  Stream<RemoteMessage> get notificationTaps =>
      FirebaseMessaging.onMessageOpenedApp;

  Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _listenForTokenRefresh() {
    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((token) async {
          final account = _registeredAccount;
          if (account == null) {
            return;
          }
          try {
            await _registerToken(account: account, token: token);
          } catch (error, stackTrace) {
            _logger.e(
              'FCM token refresh registration failed.',
              error: error,
              stackTrace: stackTrace,
            );
          }
        });
  }

  Future<void> _registerToken({
    required MailAccount account,
    required String token,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final uri = Uri.parse('$_pushApiBaseUrl/api/devices/');
    final response = await http
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
            'X-Device-Registration-Secret': _deviceRegistrationSecret,
          },
          body: jsonEncode({
            'accountId': account.id,
            'email': account.email,
            'fcmToken': token,
            'platform': _platformName(),
            'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'FCM token registration failed: ${response.statusCode} ${response.body}',
      );
    }

    _setStatus(PushRegistrationStatus.success(account.email));
    _logger.i('FCM token registered for ${account.email}.');
  }

  String _platformName() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
  }

  void _setStatus(PushRegistrationStatus status) {
    _onStatusChanged?.call(status);
  }
}

enum PushRegistrationState { idle, registering, success, skipped, failure }

class PushRegistrationStatus {
  const PushRegistrationStatus({
    required this.state,
    required this.message,
    required this.updatedAt,
  });

  final PushRegistrationState state;
  final String message;
  final DateTime updatedAt;

  factory PushRegistrationStatus.idle() => PushRegistrationStatus(
    state: PushRegistrationState.idle,
    message: 'Not registered yet.',
    updatedAt: DateTime.now(),
  );

  factory PushRegistrationStatus.registering(String email) =>
      PushRegistrationStatus(
        state: PushRegistrationState.registering,
        message: 'Registering push token for $email...',
        updatedAt: DateTime.now(),
      );

  factory PushRegistrationStatus.success(String email) => PushRegistrationStatus(
    state: PushRegistrationState.success,
    message: 'Push token registered for $email.',
    updatedAt: DateTime.now(),
  );

  factory PushRegistrationStatus.skipped(String message) =>
      PushRegistrationStatus(
        state: PushRegistrationState.skipped,
        message: message,
        updatedAt: DateTime.now(),
      );

  factory PushRegistrationStatus.failure(String message) =>
      PushRegistrationStatus(
        state: PushRegistrationState.failure,
        message: message,
        updatedAt: DateTime.now(),
      );
}
