import 'package:finestar_mail/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FinestarMailApp()));

    await tester.pump();

    expect(find.text('FS Mail'), findsOneWidget);
  });
}
