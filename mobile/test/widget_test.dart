import 'dart:convert';

import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/app/brandguard_app.dart';
import 'package:brandguard/features/auth/sign_in_screen.dart';
import 'package:brandguard/features/dashboard/home_dashboard_screen.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
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
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/config') {
        return http.Response(
          '{"auth_provider":"local","demo_accounts_enabled":true}',
          200,
        );
      }
      if (request.url.path == '/api/v1/auth/login') {
        final body = jsonDecode(request.body);
        final account = DemoAuth.findAccount(body['email']);
        if (account == null || body['password'] != DemoAuth.password) {
          return http.Response('{"detail":"Incorrect email or password"}', 401);
        }
        return http.Response(
          jsonEncode({
            'access_token': 'access-${account.userId}',
            'refresh_token': 'refresh-${account.userId}',
            'user': {
              'user_id': account.userId,
              'name': account.name,
              'email': account.email,
              'role': account.role,
            },
          }),
          200,
        );
      }
      return http.Response(
        '{"total_checks":0,"pending":0,"approved":0,"rejected":0,"unread":0,"database":"sqlite","auth_provider":"local","ai_configured":false}',
        200,
      );
    });
  });
  tearDown(() {
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });
  Future<void> openLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await settleTestUi(tester);
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('demo-sign-in'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settleTestUi(tester);
  }

  testWidgets('splash opens password login and visible enabled demo autofill', (
    tester,
  ) async {
    await tester.pumpWidget(const BrandGuardApp());
    await tester.pump(const Duration(milliseconds: 2700));
    await settleTestUi(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Password for both: Demo@12345'), findsOneWidget);
    expect(session.userId, isNull);
  });
  for (final account in DemoAuth.accounts) {
    testWidgets(
      '${account.role} signs in through server and keeps passwords/tokens out of preferences',
      (tester) async {
        await openLogin(tester);
        await tester.ensureVisible(
          find.byKey(ValueKey('demo-${account.role}')),
        );
        await tester.tap(find.byKey(ValueKey('demo-${account.role}')));
        await submit(tester);
        expect(find.byType(HomeDashboardScreen), findsOneWidget);
        expect(session.userId, account.userId);
        expect(session.accessToken, 'access-${account.userId}');
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          expect(prefs.get(key), isNot(DemoAuth.password));
          expect(key.contains('token'), isFalse);
          expect(key.contains('password'), isFalse);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'wrong password displays server error without creating a session',
    (tester) async {
      await openLogin(tester);
      await tester.enterText(
        find.byKey(const ValueKey('demo-email')),
        DemoAuth.creator.email,
      );
      await tester.enterText(
        find.byKey(const ValueKey('demo-password')),
        'incorrect',
      );
      await submit(tester);
      expect(
        find.textContaining('Incorrect email or password'),
        findsOneWidget,
      );
      expect(session.accessToken, isNull);
    },
  );
  testWidgets('offline backend cannot be bypassed with demo credentials', (
    tester,
  ) async {
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async => throw http.ClientException('Backend offline'),
    );
    await openLogin(tester);
    expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('demo-email')),
      DemoAuth.creator.email,
    );
    await tester.enterText(
      find.byKey(const ValueKey('demo-password')),
      DemoAuth.password,
    );
    await submit(tester);
    expect(
      find.textContaining('Cannot reach the BrandGuard server'),
      findsWidgets,
    );
    expect(find.textContaining('SocketException'), findsNothing);
    expect(session.currentUser, isNull);
  });
  testWidgets('remember email does not restore authentication', (tester) async {
    SharedPreferences.setMockInitialValues({
      DemoAuth.rememberedEmailKey: DemoAuth.reviewer.email,
      DemoAuth.rememberEmailKey: true,
    });
    await openLogin(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('demo-email')))
          .controller
          ?.text,
      DemoAuth.reviewer.email,
    );
    expect(session.currentUser, isNull);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('demo-password')))
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('demo-password')),
      DemoAuth.password,
    );
    await submit(tester);
    expect(session.role, 'reviewer');
  });
  testWidgets('cloud config hides public demo values', (tester) async {
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async => http.Response(
        '{"auth_provider":"supabase","demo_accounts_enabled":false}',
        200,
      ),
    );
    await openLogin(tester);
    expect(find.byKey(const ValueKey('demo-access-card')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('demo-email')))
          .controller
          ?.text,
      isEmpty,
    );
  });
  testWidgets('signout clears tokens and returns to sign-in', (tester) async {
    session.signIn(
      DemoAuth.reviewer.user,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await settleTestUi(tester);
    final button = find.byKey(const ValueKey('demo-sign-out'));
    await tester.scrollUntilVisible(button, 250);
    await tester.tap(button);
    await settleTestUi(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Sign Out'));
    await settleTestUi(tester);
    expect(session.currentUser, isNull);
    expect(session.refreshToken, isNull);
    expect(find.byType(SignInScreen), findsOneWidget);
  });
  testWidgets(
    'signup dialog can be opened and dismissed without disposed-controller errors',
    (tester) async {
      await openLogin(tester);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await settleTestUi(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settleTestUi(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('local recovery exposes unavailable email honestly', (
    tester,
  ) async {
    BrandGuardApiService.clientForTesting = MockClient(
      (request) async => request.url.path.endsWith('/recover')
          ? http.Response(
              '{"detail":"Email reset needs Supabase configuration"}',
              503,
            )
          : http.Response(
              '{"auth_provider":"local","demo_accounts_enabled":true}',
              200,
            ),
    );
    await openLogin(tester);
    await tester.enterText(
      find.byKey(const ValueKey('demo-email')),
      DemoAuth.creator.email,
    );
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await settleTestUi(tester);
    await tester.tap(find.text('Send instructions'));
    await settleTestUi(tester);
    expect(find.textContaining('Email reset needs Supabase'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleTestUi(tester);
    expect(tester.takeException(), isNull);
  });
}
