import 'package:finestar_mail/features/auth/domain/entities/connection_settings.dart';
import 'package:finestar_mail/features/auth/domain/entities/mail_account.dart';
import 'package:finestar_mail/features/notifications/data/mail_notification_payload.dart';
import 'package:finestar_mail/features/notifications/presentation/in_app_mail_notification_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats foreground mail banner with account sender and subject', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(inAppMailNotificationControllerProvider.notifier)
        .showMailBanner(
          const MailNotificationPayload(
            accountEmail: 'sales@example.test',
            sender: 'Ivan Horvat',
            subject: 'Ponuda za travanj',
          ),
          account: _account,
          duration: const Duration(minutes: 1),
        );

    final notification = container.read(
      inAppMailNotificationControllerProvider,
    );
    expect(notification?.title, 'New mail on sales@example.test');
    expect(notification?.body, 'Ivan Horvat - Ponuda za travanj');
  });

  test('falls back gracefully when notification fields are missing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(inAppMailNotificationControllerProvider.notifier)
        .showMailBanner(
          const MailNotificationPayload(),
          duration: const Duration(minutes: 1),
        );

    final notification = container.read(
      inAppMailNotificationControllerProvider,
    );
    expect(notification?.title, 'New mail');
    expect(notification?.body, 'You have a new message.');
  });

  test('new foreground mail banner replaces the current banner', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      inAppMailNotificationControllerProvider.notifier,
    );

    controller.showMailBanner(
      const MailNotificationPayload(subject: 'First'),
      duration: const Duration(minutes: 1),
    );
    final first = container.read(inAppMailNotificationControllerProvider);
    controller.showMailBanner(
      const MailNotificationPayload(subject: 'Second'),
      duration: const Duration(minutes: 1),
    );

    final second = container.read(inAppMailNotificationControllerProvider);
    expect(second?.id, isNot(first?.id));
    expect(second?.body, 'Second');
  });

  test('banner can be dismissed manually', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      inAppMailNotificationControllerProvider.notifier,
    );

    controller.showMailBanner(
      const MailNotificationPayload(subject: 'Dismiss me'),
      duration: const Duration(minutes: 1),
    );
    controller.dismiss();

    expect(container.read(inAppMailNotificationControllerProvider), isNull);
  });

  test('banner auto-dismisses after the configured duration', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(inAppMailNotificationControllerProvider.notifier)
        .showMailBanner(
          const MailNotificationPayload(subject: 'Short lived'),
          duration: const Duration(milliseconds: 10),
        );

    expect(container.read(inAppMailNotificationControllerProvider), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(inAppMailNotificationControllerProvider), isNull);
  });
}

final _account = MailAccount(
  id: 'sales@example.test',
  email: 'sales@example.test',
  displayName: 'Sales',
  connectionSettings: const ConnectionSettings(
    imapHost: 'mail.example.test',
    imapPort: 993,
    imapSecurity: MailSecurity.sslTls,
    smtpHost: 'mail.example.test',
    smtpPort: 465,
    smtpSecurity: MailSecurity.sslTls,
  ),
  createdAt: DateTime(2026, 4, 17),
);
