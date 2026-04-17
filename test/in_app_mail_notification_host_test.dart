import 'package:finestar_mail/features/notifications/data/mail_notification_payload.dart';
import 'package:finestar_mail/features/notifications/presentation/in_app_mail_notification_controller.dart';
import 'package:finestar_mail/features/notifications/presentation/in_app_mail_notification_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('host shows and dismisses top mail banner', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: InAppMailNotificationHost(child: Scaffold(body: Text('Inbox'))),
        ),
      ),
    );

    container
        .read(inAppMailNotificationControllerProvider.notifier)
        .showMailBanner(
          const MailNotificationPayload(
            accountEmail: 'sales@example.test',
            sender: 'Ivan Horvat',
            subject: 'Ponuda za travanj',
          ),
          duration: const Duration(minutes: 1),
        );
    await tester.pump();

    expect(find.text('New mail on sales@example.test'), findsOneWidget);
    expect(find.text('Ivan Horvat - Ponuda za travanj'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('New mail on sales@example.test'), findsNothing);
    expect(find.text('Inbox'), findsOneWidget);
  });
}
