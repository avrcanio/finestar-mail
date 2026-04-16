import 'package:finestar_mail/app/app.dart';
import 'package:finestar_mail/app/providers.dart';
import 'package:finestar_mail/features/notifications/data/device_registration_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceRegistrationConfigProvider.overrideWith(
            (ref) async => const DeviceRegistrationConfig(
              apiBaseUrl: '',
              registrationSecret: '',
            ),
          ),
        ],
        child: const FinestarMailApp(),
      ),
    );

    await tester.pump();

    expect(find.text('FS Mail'), findsOneWidget);
  });
}
