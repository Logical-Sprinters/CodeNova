
import 'package:flutter_test/flutter_test.dart';
import 'package:brandguard/main.dart';

void main() {
  testWidgets('BrandGuard app launches successfully',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BrandGuardApp());

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('BrandGuard'), findsOneWidget);
  });
}
