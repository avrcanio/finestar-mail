import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/entities/mail_account.dart';
import '../data/mail_notification_payload.dart';

final inAppMailNotificationControllerProvider =
    NotifierProvider<InAppMailNotificationController, InAppMailNotification?>(
      InAppMailNotificationController.new,
    );

class InAppMailNotification {
  const InAppMailNotification({
    required this.id,
    required this.payload,
    required this.account,
  });

  final int id;
  final MailNotificationPayload payload;
  final MailAccount? account;

  String get accountLabel {
    final accountEmail = account?.email.trim();
    if (accountEmail != null && accountEmail.isNotEmpty) {
      return accountEmail;
    }
    final payloadEmail = payload.accountEmail?.trim();
    if (payloadEmail != null && payloadEmail.isNotEmpty) {
      return payloadEmail;
    }
    return '';
  }

  String get title {
    final account = accountLabel;
    return account.isEmpty ? 'New mail' : 'New mail on $account';
  }

  String get body {
    final sender = payload.sender?.trim();
    final subject = payload.subject?.trim();
    if (sender != null &&
        sender.isNotEmpty &&
        subject != null &&
        subject.isNotEmpty) {
      return '$sender - $subject';
    }
    if (subject != null && subject.isNotEmpty) {
      return subject;
    }
    if (sender != null && sender.isNotEmpty) {
      return sender;
    }
    return 'You have a new message.';
  }
}

class InAppMailNotificationController extends Notifier<InAppMailNotification?> {
  static const defaultDuration = Duration(seconds: 5);

  Timer? _dismissTimer;
  int _nextId = 0;

  @override
  InAppMailNotification? build() {
    ref.onDispose(() => _dismissTimer?.cancel());
    return null;
  }

  void showMailBanner(
    MailNotificationPayload payload, {
    MailAccount? account,
    Duration duration = defaultDuration,
  }) {
    _dismissTimer?.cancel();
    state = InAppMailNotification(
      id: _nextId++,
      payload: payload,
      account: account,
    );
    _dismissTimer = Timer(duration, dismiss);
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    state = null;
  }
}
