import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Use the same bundled font as the application. No network or fake assets.
void configureTestFonts() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-Variable.ttf'));
    await loader.load();
  });
}

Future<void> settleTestUi(WidgetTester tester) => tester.pumpAndSettle();
