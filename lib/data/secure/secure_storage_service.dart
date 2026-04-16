import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? secureStorage])
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _accountKey = 'active_account';
  static const _passwordKey = 'active_account_password';

  final FlutterSecureStorage _secureStorage;

  Future<void> saveAccount({
    required Map<String, dynamic> accountJson,
    required String password,
  }) async {
    await _secureStorage.write(
      key: _accountKey,
      value: jsonEncode(accountJson),
    );
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<Map<String, dynamic>?> readAccount() async {
    final value = await _secureStorage.read(key: _accountKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return jsonDecode(value) as Map<String, dynamic>;
  }

  Future<String?> readPassword() => _secureStorage.read(key: _passwordKey);

  Future<void> clear() async {
    await _secureStorage.delete(key: _accountKey);
    await _secureStorage.delete(key: _passwordKey);
  }
}
