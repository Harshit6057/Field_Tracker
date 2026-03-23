import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:employee_location_tracker/app.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: EmployeeLocationTrackerApp(),
      ),
    );

    expect(find.text('Office Location Tracker'), findsOneWidget);
  });
}
