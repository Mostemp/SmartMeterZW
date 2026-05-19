import 'package:flutter_test/flutter_test.dart';
import 'package:smartmeter_zw/main.dart';

void main() {
  testWidgets('SmartMeter ZW login screen render test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartMeterApp());

    // Verify that login screen elements render correctly.
    expect(find.text('SmartMeter ZW'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Demo: admin / 1234 / 1234567890'), findsOneWidget);
  });
}
