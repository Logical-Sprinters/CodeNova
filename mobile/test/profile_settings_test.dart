import 'dart:convert';

import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget_test_setup.dart';

/// Profile settings that must actually persist.
///
/// The bug this locks down: editing the display name used to change nothing on
/// screen and nothing on the server. These tests assert the real contract —
/// request sent, session updated, UI repainted, preferences round-tripped.
void main() {
  configureTestFonts();

  late List<http.Request> sent;
  late Map<String, dynamic> prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sent = [];
    prefs = {
      'email_updates': true,
      'review_activity': true,
      'product_news': false,
    };
    session.signIn(DemoAuth.reviewer.user, accessToken: 'test-access');

    BrandGuardApiService.clientForTesting = MockClient((request) async {
      sent.add(request);
      final path = request.url.path;
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;

      if (path == '/api/v1/auth/profile' && request.method == 'PATCH') {
        final name = (body['name'] as String?) ?? '';
        if (name.trim().length < 2) {
          return http.Response(
            '{"detail":[{"msg":"Display name must contain at least two characters"}]}',
            422,
          );
        }
        final user = session.currentUser!;
        return http.Response(
          jsonEncode({
            'user': {
              'user_id': user.userId,
              'email': user.email,
              'name': name.trim(),
              'role': user.role,
            },
            'message': 'Display name updated',
          }),
          200,
        );
      }
      if (path == '/api/v1/auth/preferences') {
        if (request.method == 'PUT') {
          prefs = {
            for (final key in prefs.keys) key: body[key] as bool? ?? prefs[key],
          };
          return http.Response(jsonEncode(prefs), 200);
        }
        return http.Response(jsonEncode(prefs), 200);
      }
      if (path == '/api/v1/system/status') {
        return http.Response('{"auth_provider":"supabase"}', 200);
      }
      return http.Response('{"items":[],"total":0,"unread":0}', 200);
    });
  });

  tearDown(() => session.signOut());

  testWidgets('editing the display name saves to the server and repaints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // The old name is on screen.
    final oldName = session.currentUser!.name;
    expect(find.text(oldName), findsWidgets);

    await tester.tap(find.text('Edit display name'));
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Meera Sharma');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // 1. The request really went to the server.
    final patch = sent.where(
      (r) => r.url.path == '/api/v1/auth/profile' && r.method == 'PATCH',
    );
    expect(patch, hasLength(1));
    expect(jsonDecode(patch.first.body)['name'], 'Meera Sharma');

    // 2. The session (what every screen reads) was updated.
    expect(session.currentUser!.name, 'Meera Sharma');

    // 3. The UI shows the new name without a reload.
    expect(find.text('Meera Sharma'), findsWidgets);
    expect(find.text(oldName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a too-short name is rejected before any request is sent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final before = session.currentUser!.name;
    await tester.tap(find.text('Edit display name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      sent.where((r) => r.url.path == '/api/v1/auth/profile'),
      isEmpty,
      reason: 'validation must run before the network call',
    );
    expect(session.currentUser!.name, before);
  });

  testWidgets('a server failure keeps the old name and shows the error', (
    tester,
  ) async {
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/profile') {
        return http.Response('{"detail":"Session expired"}', 401);
      }
      return http.Response('{}', 200);
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final before = session.currentUser!.name;

    await tester.tap(find.text('Edit display name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Meera Sharma');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(session.currentUser!.name, before, reason: 'no fake success');
    expect(find.textContaining('Could not save the name'), findsOneWidget);
  });

  testWidgets('notification preferences load and save through the server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // The row summarises the stored preferences (all three default states).
    expect(find.textContaining('2 of 3 enabled'), findsOneWidget);

    final listView = find.byType(ListView);
    final row = find.text('Notification preferences');
    for (var i = 0; i < 14 && tester.getRect(row).bottom > 900; i++) {
      await tester.drag(listView.first, const Offset(0, -240));
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(row);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    expect(find.text('Account & security emails'), findsOneWidget);
    expect(find.text('Product announcements'), findsOneWidget);

    // Flip the third preference; it must be saved on the server immediately.
    final switches = find.byType(SwitchListTile);
    expect(switches, findsNWidgets(3));
    await tester.tap(switches.at(2));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(prefs['product_news'], isTrue);
    expect(
      sent.where(
        (r) => r.url.path == '/api/v1/auth/preferences' && r.method == 'PUT',
      ),
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
