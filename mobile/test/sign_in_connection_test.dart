import 'dart:async';

import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/auth/create_account_screen.dart';
import 'package:brandguard/features/auth/sign_in_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget_test_setup.dart';

void main() {
  configureTestFonts();
  setUp(() {
    session.signOut();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });

  Future<void> open(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await settleTestUi(tester);
  }

  http.Response cloudConfig() => http.Response(
    '{"auth_provider":"supabase","demo_accounts_enabled":false}',
    200,
  );

  testWidgets(
    'initial loading never exposes local demo values or a seeded password',
    (tester) async {
      final gate = Completer<http.Response>();
      BrandGuardApiService.clientForTesting = MockClient((_) => gate.future);
      await open(tester);
      expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('demo-email')))
            .controller
            ?.text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('demo-password')))
            .controller
            ?.text,
        isEmpty,
      );
      gate.complete(
        http.Response(
          '{"auth_provider":"local","demo_accounts_enabled":true}',
          200,
        ),
      );
      await settleTestUi(tester);
      expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
      expect(find.text('Password for both: Demo@12345'), findsNothing);
    },
  );

  testWidgets(
    'unreachable config stays fail-closed and Retry rechecks the server',
    (tester) async {
      var online = false;
      BrandGuardApiService.clientForTesting = MockClient((_) async {
        if (!online) {
          throw http.ClientException('SocketException 10.0.2.2:8000 errno 110');
        }
        return cloudConfig();
      });
      await open(tester);
      expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
      expect(
        find.textContaining('Cannot reach the BrandGuard server'),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
      online = true;
      await tester.tap(find.byKey(const ValueKey('retry-connection')));
      await settleTestUi(tester);
      expect(find.text('Connected to live service'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-connection')), findsNothing);
      expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
    },
  );

  testWidgets(
    'cloud server cannot enable local credentials with a conflicting flag',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => http.Response(
          '{"auth_provider":"supabase","demo_accounts_enabled":true}',
          200,
        ),
      );
      await open(tester);
      expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
      expect(find.text('Password for both: Demo@12345'), findsNothing);
      expect(find.textContaining('Keep your backend running'), findsNothing);
      expect(find.textContaining('Server:'), findsOneWidget);
    },
  );

  testWidgets(
    'old remembered local email is not suggested as a hosted account',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        DemoAuth.rememberEmailKey: true,
        DemoAuth.rememberedEmailKey: DemoAuth.creator.email,
      });
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => cloudConfig(),
      );
      await open(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('demo-email')))
            .controller
            ?.text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('demo-password')))
            .controller
            ?.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'empty or invalid login is validated before sending credentials',
    (tester) async {
      var logins = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path.endsWith('/login')) logins++;
        return cloudConfig();
      });
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('demo-sign-in')));
      await tester.tap(find.byKey(const ValueKey('demo-sign-in')));
      await settleTestUi(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(logins, 0);
      expect(session.currentUser, isNull);
    },
  );

  testWidgets(
    'email confirmation is a success notice, not an error or a fake login',
    (tester) async {
      var signups = 0, logins = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path.endsWith('/signup')) {
          signups++;
          return http.Response(
            '{"requires_confirmation":true,"message":"Confirm email"}',
            200,
          );
        }
        if (request.url.path.endsWith('/login')) logins++;
        return cloudConfig();
      });
      await open(tester);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await settleTestUi(tester);
      await tester.enterText(
        find.byKey(const ValueKey('create-account-name')),
        'New User',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-account-email')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-account-password')),
        'Password123!',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-account-confirm')),
        'Password123!',
      );
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Checkbox));
      await settleTestUi(tester);
      final create = find.byKey(const ValueKey('create-account'));
      await tester.scrollUntilVisible(
        create,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(create);
      await settleTestUi(tester);
      expect(find.byType(CreateAccountScreen), findsNothing);
      expect(find.byKey(const ValueKey('auth-notice')), findsOneWidget);
      expect(
        find.textContaining('Confirm your email if required, then sign in'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('demo-login-error')), findsNothing);
      expect(session.currentUser, isNull);
      expect(signups, 1);
      expect(logins, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('demo-email')))
            .controller
            ?.text,
        'user@example.com',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timeout restores Sign In and fits a narrow mobile screen', (
    tester,
  ) async {
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        throw TimeoutException('SocketException raw internal failure');
      }
      return cloudConfig();
    });
    await open(tester, width: 320);
    await tester.enterText(
      find.byKey(const ValueKey('demo-email')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('demo-password')),
      'Password123!',
    );
    final button = find.byKey(const ValueKey('demo-sign-in'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settleTestUi(tester);
    expect(find.textContaining('Connection timed out.'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(session.currentUser, isNull);
    expect(tester.takeException(), isNull);
  });
}
