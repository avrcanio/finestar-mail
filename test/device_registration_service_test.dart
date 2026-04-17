import 'dart:convert';

import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/notifications/data/device_registration_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'registerAccount posts device token with secret header and payload',
    () async {
      http.Request? capturedRequest;
      var permissionRequested = false;

      final service = DeviceRegistrationService(
        config: const DeviceRegistrationConfig(
          apiBaseUrl: 'https://mail.example.test/',
          registrationSecret: 'registration-secret',
        ),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response('{}', 201);
        }),
        fcmTokenLoader: () async => 'fcm-token',
        authTokenLoader: (_) async => 'drf-token',
        permissionRequester: () async => permissionRequested = true,
        appVersionLoader: () async => '1.0.0+1',
        platform: 'android',
      );

      final registered = await service.registerAccount(_account);

      expect(registered, isTrue);
      expect(permissionRequested, isTrue);
      expect(
        capturedRequest?.url.toString(),
        'https://mail.example.test/api/devices/',
      );
      expect(
        capturedRequest?.headers['X-Device-Registration-Secret'],
        'registration-secret',
      );
      expect(capturedRequest?.headers['Authorization'], 'Token drf-token');
      expect(capturedRequest?.headers['Content-Type'], 'application/json');

      final payload = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
      expect(payload, {
        'account_email': _account.email,
        'fcm_token': 'fcm-token',
        'platform': 'android',
        'app_version': '1.0.0+1',
      });
    },
  );

  test('registerAccount is disabled when config is missing', () async {
    final service = DeviceRegistrationService(
      config: const DeviceRegistrationConfig(
        apiBaseUrl: '',
        registrationSecret: '',
      ),
      httpClient: MockClient((request) async {
        fail('HTTP should not be called when notification config is missing.');
      }),
      fcmTokenLoader: () async => 'fcm-token',
      authTokenLoader: (_) async => 'drf-token',
      permissionRequester: () async {},
      appVersionLoader: () async => '1.0.0+1',
      platform: 'android',
    );

    final registered = await service.registerAccount(_account);

    expect(registered, isFalse);
  });

  test('registerAccount is disabled when FCM token is unavailable', () async {
    final service = DeviceRegistrationService(
      config: const DeviceRegistrationConfig(
        apiBaseUrl: 'https://mail.example.test',
        registrationSecret: 'registration-secret',
      ),
      httpClient: MockClient((request) async {
        fail('HTTP should not be called without an FCM token.');
      }),
      fcmTokenLoader: () async => null,
      authTokenLoader: (_) async => 'drf-token',
      permissionRequester: () async {},
      appVersionLoader: () async => '1.0.0+1',
      platform: 'android',
    );

    final registered = await service.registerAccount(_account);

    expect(registered, isFalse);
  });

  test('registerAccount is disabled when auth token is unavailable', () async {
    final service = DeviceRegistrationService(
      config: const DeviceRegistrationConfig(
        apiBaseUrl: 'https://mail.example.test',
        registrationSecret: 'registration-secret',
      ),
      httpClient: MockClient((request) async {
        fail('HTTP should not be called without an auth token.');
      }),
      fcmTokenLoader: () async => 'fcm-token',
      authTokenLoader: (_) async => null,
      permissionRequester: () async {},
      appVersionLoader: () async => '1.0.0+1',
      platform: 'android',
    );

    final registered = await service.registerAccount(_account);

    expect(registered, isFalse);
  });

  test(
    'registerAccount returns false for backend registration failures',
    () async {
      for (final failure in const [
        _RegistrationFailure(401, 'not_authenticated'),
        _RegistrationFailure(401, 'mailbox_credentials_missing'),
        _RegistrationFailure(403, 'account_email_mismatch'),
        _RegistrationFailure(403, 'invalid_registration_secret'),
        _RegistrationFailure(400, 'invalid_request'),
      ]) {
        final service = DeviceRegistrationService(
          config: const DeviceRegistrationConfig(
            apiBaseUrl: 'https://mail.example.test',
            registrationSecret: 'registration-secret',
          ),
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({'error': failure.errorCode}),
              failure.statusCode,
            );
          }),
          fcmTokenLoader: () async => 'fcm-token',
          authTokenLoader: (_) async => 'drf-token',
          permissionRequester: () async {},
          appVersionLoader: () async => '1.0.0+1',
          platform: 'android',
        );

        final registered = await service.registerAccount(_account);

        expect(
          registered,
          isFalse,
          reason: '${failure.statusCode} ${failure.errorCode}',
        );
      }
    },
  );

  test('registerAccounts posts one current token for every account', () async {
    final capturedRequests = <http.Request>[];
    var permissionRequests = 0;
    var tokenLoads = 0;
    var versionLoads = 0;

    final service = DeviceRegistrationService(
      config: const DeviceRegistrationConfig(
        apiBaseUrl: 'https://mail.example.test',
        registrationSecret: 'registration-secret',
      ),
      httpClient: MockClient((request) async {
        capturedRequests.add(request);
        return http.Response('{}', 201);
      }),
      fcmTokenLoader: () async {
        tokenLoads++;
        return 'shared-fcm-token';
      },
      authTokenLoader: (accountId) async => 'token-for-$accountId',
      permissionRequester: () async => permissionRequests++,
      appVersionLoader: () async {
        versionLoads++;
        return '1.0.0+1';
      },
      platform: 'android',
    );

    final results = await service.registerAccounts([_account, _backupAccount]);

    expect(results, {_account.id: true, _backupAccount.id: true});
    expect(permissionRequests, 1);
    expect(tokenLoads, 1);
    expect(versionLoads, 1);
    expect(capturedRequests, hasLength(2));
    expect(
      capturedRequests.map((request) => request.headers['Authorization']),
      [
        'Token token-for-avrcan@finestar.hr',
        'Token token-for-backup@finestar.hr',
      ],
    );
    expect(
      capturedRequests
          .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
          .map((body) => body['fcm_token']),
      ['shared-fcm-token', 'shared-fcm-token'],
    );
  });

  test('registerAccounts continues after one account fails', () async {
    final capturedEmails = <String>[];
    final service = DeviceRegistrationService(
      config: const DeviceRegistrationConfig(
        apiBaseUrl: 'https://mail.example.test',
        registrationSecret: 'registration-secret',
      ),
      httpClient: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final email = payload['account_email'] as String;
        capturedEmails.add(email);
        return http.Response('{}', email == _account.email ? 500 : 201);
      }),
      fcmTokenLoader: () async => 'fcm-token',
      authTokenLoader: (_) async => 'drf-token',
      permissionRequester: () async {},
      appVersionLoader: () async => '1.0.0+1',
      platform: 'android',
    );

    final results = await service.registerAccounts([_account, _backupAccount]);

    expect(results, {_account.id: false, _backupAccount.id: true});
    expect(capturedEmails, [_account.email, _backupAccount.email]);
  });

  test(
    'dev config loader reads local asset when dart defines are absent',
    () async {
      final loader = DeviceRegistrationConfigLoader(
        assetBundle: _FakeAssetBundle(
          jsonEncode({
            'apiBaseUrl': 'https://mail.finestar.hr',
            'deviceRegistrationSecret': 'local-secret',
          }),
        ),
      );

      final config = await loader.load();

      expect(config.apiBaseUrl, 'https://mail.finestar.hr');
      expect(config.registrationSecret, 'local-secret');
    },
  );

  test('environment config has production backend base URL fallback', () {
    final config = DeviceRegistrationConfig.fromEnvironment();

    expect(config.apiBaseUrl, 'https://mailadmin.finestar.hr');
    expect(config.isConfigured, isFalse);
  });
}

class _RegistrationFailure {
  const _RegistrationFailure(this.statusCode, this.errorCode);

  final int statusCode;
  final String errorCode;
}

final _account = MailAccount(
  id: 'avrcan@finestar.hr',
  email: 'avrcan@finestar.hr',
  displayName: 'Ante Vrcan',
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

final _backupAccount = MailAccount(
  id: 'backup@finestar.hr',
  email: 'backup@finestar.hr',
  displayName: 'Backup Mailbox',
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

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.json);

  final String json;

  @override
  Future<ByteData> load(String key) {
    throw UnimplementedError();
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return json;
  }
}
