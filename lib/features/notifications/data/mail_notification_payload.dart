import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

class MailNotificationPayload {
  const MailNotificationPayload({
    this.accountEmail,
    this.sender,
    this.subject,
    this.folder,
    this.uid,
    this.messageId,
    this.localMessageId,
    this.receivedAt,
  });

  final String? accountEmail;
  final String? sender;
  final String? subject;
  final String? folder;
  final String? uid;
  final String? messageId;
  final String? localMessageId;
  final DateTime? receivedAt;

  bool get hasRoutingData =>
      _hasValue(localMessageId) ||
      _hasValue(uid) ||
      _hasValue(messageId) ||
      _hasValue(subject) ||
      _hasValue(sender);

  static MailNotificationPayload fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final notification = message.notification;
    return MailNotificationPayload(
      accountEmail: _firstValue(data, const [
        'accountEmail',
        'account_email',
        'email',
        'to',
      ]),
      sender:
          _firstValue(data, const ['sender', 'from']) ?? notification?.title,
      subject:
          _firstValue(data, const ['subject', 'title']) ?? notification?.body,
      folder: _firstValue(data, const ['folder', 'folderName', 'mailbox']),
      uid: _firstValue(data, const ['uid', 'messageUid', 'message_uid']),
      messageId: _firstValue(data, const [
        'messageId',
        'message_id',
        'rfcMessageId',
        'rfc_message_id',
      ]),
      localMessageId: _firstValue(data, const [
        'localMessageId',
        'local_message_id',
        'mailMessageId',
        'mail_message_id',
      ]),
      receivedAt: _dateValue(data, const ['receivedAt', 'received_at']),
    );
  }

  static MailNotificationPayload? fromLocalPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    return fromMap(decoded.cast<String, dynamic>());
  }

  static MailNotificationPayload fromMap(Map<String, dynamic> data) {
    return MailNotificationPayload(
      accountEmail: _firstValue(data, const [
        'accountEmail',
        'account_email',
        'email',
        'to',
      ]),
      sender: _firstValue(data, const ['sender', 'from']),
      subject: _firstValue(data, const ['subject', 'title']),
      folder: _firstValue(data, const ['folder', 'folderName', 'mailbox']),
      uid: _firstValue(data, const ['uid', 'messageUid', 'message_uid']),
      messageId: _firstValue(data, const [
        'messageId',
        'message_id',
        'rfcMessageId',
        'rfc_message_id',
      ]),
      localMessageId: _firstValue(data, const [
        'localMessageId',
        'local_message_id',
        'mailMessageId',
        'mail_message_id',
      ]),
      receivedAt: _dateValue(data, const ['receivedAt', 'received_at']),
    );
  }

  Map<String, String> toMap() {
    return {
      if (_hasValue(accountEmail)) 'accountEmail': accountEmail!.trim(),
      if (_hasValue(sender)) 'sender': sender!.trim(),
      if (_hasValue(subject)) 'subject': subject!.trim(),
      if (_hasValue(folder)) 'folder': folder!.trim(),
      if (_hasValue(uid)) 'uid': uid!.trim(),
      if (_hasValue(messageId)) 'messageId': messageId!.trim(),
      if (_hasValue(localMessageId)) 'localMessageId': localMessageId!.trim(),
      if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
    };
  }

  String encode() => jsonEncode(toMap());

  static String? _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (_hasValue(value)) {
        return value;
      }
    }
    return null;
  }

  static DateTime? _dateValue(Map<String, dynamic> data, List<String> keys) {
    final value = _firstValue(data, keys);
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static bool _hasValue(String? value) =>
      value != null && value.trim().isNotEmpty;
}
