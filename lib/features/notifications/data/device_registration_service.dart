import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../auth/domain/entities/mail_account.dart';

typedef FcmTokenLoader = Future<String?> Function();
typedef AuthTokenLoader = Future<String?> Function(String accountId);
typedef NotificationPermissionRequester = Future<void> Function();
typedef AppVersionLoader = Future<String> Function();

class DeviceRegistrationConfig {
  const DeviceRegistrationConfig({
    required this.apiBaseUrl,
    required this.registrationSecret,
  });

  factory DeviceRegistrationConfig.fromEnvironment() {
    return const DeviceRegistrationConfig(
      apiBaseUrl: String.fromEnvironment(
        'MAIL_NOTIFY_API_BASE_URL',
        defaultValue: 'https://mailadmin.finestar.hr',
      ),
      registrationSecret: String.fromEnvironment('DEVICE_REGISTRATION_SECRET'),
    );
  }

  factory DeviceRegistrationConfig.fromJson(Map<String, dynamic> json) {
    return DeviceRegistrationConfig(
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      registrationSecret: json['deviceRegistrationSecret'] as String? ?? '',
    );
  }

  final String apiBaseUrl;
  final String registrationSecret;

  bool get isConfigured =>
      apiBaseUrl.trim().isNotEmpty && registrationSecret.trim().isNotEmpty;

  Uri get devicesUri {
    final normalizedBase = apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase/api/devices/');
  }
}

class DeviceRegistrationConfigLoader {
  const DeviceRegistrationConfigLoader({
    this.assetPath = 'assets/config/notification_dev.json',
    this.assetBundle,
  });

  final String assetPath;
  final AssetBundle? assetBundle;

  Future<DeviceRegistrationConfig> load() async {
    final environmentConfig = DeviceRegistrationConfig.fromEnvironment();
    if (environmentConfig.isConfigured || kReleaseMode) {
      return environmentConfig;
    }

    try {
      final rawJson = await (assetBundle ?? rootBundle).loadString(assetPath);
      return DeviceRegistrationConfig.fromJson(
        jsonDecode(rawJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return environmentConfig;
    }
  }
}

class DeviceRegistrationService {
  DeviceRegistrationService({
    required DeviceRegistrationConfig config,
    required http.Client httpClient,
    required FcmTokenLoader fcmTokenLoader,
    required AuthTokenLoader authTokenLoader,
    required NotificationPermissionRequester permissionRequester,
    required AppVersionLoader appVersionLoader,
    required String platform,
    Logger? logger,
  }) : _config = config,
       _httpClient = httpClient,
       _fcmTokenLoader = fcmTokenLoader,
       _authTokenLoader = authTokenLoader,
       _permissionRequester = permissionRequester,
       _appVersionLoader = appVersionLoader,
       _platform = platform,
       _logger = logger;

  final DeviceRegistrationConfig _config;
  final http.Client _httpClient;
  final FcmTokenLoader _fcmTokenLoader;
  final AuthTokenLoader _authTokenLoader;
  final NotificationPermissionRequester _permissionRequester;
  final AppVersionLoader _appVersionLoader;
  final String _platform;
  final Logger? _logger;

  Future<Map<String, bool>> registerAccounts(List<MailAccount> accounts) async {
    if (!_config.isConfigured) {
      _logger?.i('FCM device registration skipped: config is missing.');
      return {for (final account in accounts) account.id: false};
    }
    if (accounts.isEmpty) {
      return const {};
    }

    try {
      await _permissionRequester();
      final token = await _fcmTokenLoader();
      if (token == null || token.trim().isEmpty) {
        _logger?.w('FCM device registration skipped: token is unavailable.');
        return {for (final account in accounts) account.id: false};
      }
      final appVersion = await _appVersionLoader();
      final results = <String, bool>{};
      for (final account in accounts) {
        results[account.id] = await _registerAccountWithToken(
          account: account,
          fcmToken: token.trim(),
          appVersion: appVersion,
        );
      }
      return results;
    } catch (error, stackTrace) {
      _logger?.w(
        'FCM device registration threw while preparing bulk registration.',
        error: error,
        stackTrace: stackTrace,
      );
      return {for (final account in accounts) account.id: false};
    }
  }

  Future<bool> registerAccount(MailAccount account) async {
    if (!_config.isConfigured) {
      _logger?.i('FCM device registration skipped: config is missing.');
      return false;
    }

    try {
      await _permissionRequester();
      final token = await _fcmTokenLoader();
      if (token == null || token.trim().isEmpty) {
        _logger?.w('FCM device registration skipped: token is unavailable.');
        return false;
      }
      return _registerAccountWithToken(
        account: account,
        fcmToken: token.trim(),
        appVersion: await _appVersionLoader(),
      );
    } catch (error, stackTrace) {
      _logger?.w(
        'FCM device registration threw for ${account.email}.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> _registerAccountWithToken({
    required MailAccount account,
    required String fcmToken,
    required String appVersion,
  }) async {
    try {
      final authToken = await _authTokenLoader(account.id);
      if (authToken == null || authToken.trim().isEmpty) {
        _logger?.w(
          'FCM device registration skipped: auth token is unavailable for '
          '${account.email}.',
        );
        return false;
      }

      _logger?.i(
        'Registering FCM device for ${account.email} at ${_config.devicesUri}.',
      );
      final response = await _httpClient.post(
        _config.devicesUri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Token ${authToken.trim()}',
          'X-Device-Registration-Secret': _config.registrationSecret,
        },
        body: jsonEncode({
          'account_email': account.email,
          'fcm_token': fcmToken,
          'platform': _platform,
          'app_version': appVersion,
        }),
      );

      final registered =
          response.statusCode >= 200 && response.statusCode < 300;
      if (registered) {
        _logger?.i(
          'FCM device registration succeeded for ${account.email}: '
          '${response.statusCode} ${response.body}',
        );
      } else {
        final errorCode = _errorCode(response.body);
        _logger?.w(
          'FCM device registration failed for ${account.email}: '
          '${response.statusCode} ${errorCode ?? response.body}',
        );
      }
      return registered;
    } catch (error, stackTrace) {
      _logger?.w(
        'FCM device registration threw for ${account.email}.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
