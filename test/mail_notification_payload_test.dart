import 'package:finestar_mail/features/notifications/data/mail_notification_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local notification payload round-trips mail routing fields', () {
    final payload = MailNotificationPayload(
      accountEmail: 'avrcan@finestar.hr',
      sender: 'Ante <ante@finestar.hr>',
      subject: 'Probni mail',
      folder: 'INBOX',
      uid: '42',
      messageId: '<message@finestar.hr>',
      localMessageId: 'avrcan@finestar.hr:inbox:imap:42',
      receivedAt: DateTime.utc(2026, 4, 16, 7),
    );

    final decoded = MailNotificationPayload.fromLocalPayload(payload.encode());

    expect(decoded?.accountEmail, 'avrcan@finestar.hr');
    expect(decoded?.sender, 'Ante <ante@finestar.hr>');
    expect(decoded?.subject, 'Probni mail');
    expect(decoded?.folder, 'INBOX');
    expect(decoded?.uid, '42');
    expect(decoded?.messageId, '<message@finestar.hr>');
    expect(decoded?.localMessageId, 'avrcan@finestar.hr:inbox:imap:42');
    expect(decoded?.receivedAt, DateTime.utc(2026, 4, 16, 7));
  });

  test('canonical backend payload parses routing fields', () {
    final payload = MailNotificationPayload.fromMap({
      'accountEmail': 'avrcan@finestar.hr',
      'folder': 'INBOX',
      'uid': '123',
      'messageId': '<backend-message@finestar.hr>',
      'receivedAt': '2026-04-16T07:15:00Z',
    });

    expect(payload.accountEmail, 'avrcan@finestar.hr');
    expect(payload.folder, 'INBOX');
    expect(payload.uid, '123');
    expect(payload.messageId, '<backend-message@finestar.hr>');
    expect(payload.receivedAt, DateTime.parse('2026-04-16T07:15:00Z'));
  });

  test('missing optional backend routing fields parses safely', () {
    final payload = MailNotificationPayload.fromMap({
      'accountEmail': 'avrcan@finestar.hr',
      'receivedAt': 'not-a-date',
    });

    expect(payload.accountEmail, 'avrcan@finestar.hr');
    expect(payload.folder, isNull);
    expect(payload.uid, isNull);
    expect(payload.messageId, isNull);
    expect(payload.receivedAt, isNull);
  });
}
