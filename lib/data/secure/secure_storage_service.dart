import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? secureStorage])
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _activeAccountIdKey = 'active_account_id';

  final FlutterSecureStorage _secureStorage;

  Future<void> saveActiveAccountId(String accountId) {
    return _secureStorage.write(key: _activeAccountIdKey, value: accountId);
  }

  Future<String?> readActiveAccountId() {
    return _secureStorage.read(key: _activeAccountIdKey);
  }

  Future<void> savePassword({
    required String accountId,
    required String password,
  }) {
    return _secureStorage.write(key: _passwordKey(accountId), value: password);
  }

  Future<String?> readPassword(String accountId) {
    return _secureStorage.read(key: _passwordKey(accountId));
  }

  Future<void> deletePassword(String accountId) {
    return _secureStorage.delete(key: _passwordKey(accountId));
  }

  Future<void> clearActiveAccountId() {
    return _secureStorage.delete(key: _activeAccountIdKey);
  }

  Future<void> migrateLegacyAccountIfPresent({
    required Future<void> Function(Map<String, dynamic> accountJson)
    saveAccount,
  }) async {
    const legacyAccountKey = 'active_account';
    const legacyPasswordKey = 'active_account_password';
    final value = await _secureStorage.read(key: legacyAccountKey);
    if (value == null || value.isEmpty) {
      return;
    }

    final accountJson = jsonDecode(value) as Map<String, dynamic>;
    final accountId = accountJson['id'] as String;
    final password = await _secureStorage.read(key: legacyPasswordKey);
    await saveAccount(accountJson);
    await saveActiveAccountId(accountId);
    if (password != null) {
      await savePassword(accountId: accountId, password: password);
    }
    await _secureStorage.delete(key: legacyAccountKey);
    await _secureStorage.delete(key: legacyPasswordKey);
  }

  String _passwordKey(String accountId) => 'account_password:$accountId';
}
