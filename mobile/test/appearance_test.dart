import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/app/appearance_controller.dart';
import 'package:brandguard/app/ui/app_widgets.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/analytics/analytics_screen.dart';
import 'package:brandguard/features/auth/sign_in_screen.dart';
import 'package:brandguard/features/checks/findings_evidence_screen.dart';
import 'package:brandguard/features/checks/new_brand_check_screen.dart';
import 'package:brandguard/features/dashboard/home_dashboard_screen.dart';
import 'package:brandguard/features/guidelines/guidelines_hub_screen.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
import 'package:brandguard/features/reviews/review_queue_screen.dart';
import 'package:brandguard/features/workspace/workspace_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget_test_setup.dart';

/// Dark / light / system appearance.
///
/// Every screen is rendered in both themes and must (a) build without error,
/// (b) actually paint dark surfaces and light text in dark mode, and (c) the
/// tokens must never fall back to a light value while dark is active.
void main() {
  configureTestFonts();

  final screens = <String, Widget Function()>{
    'sign in': () => const SignInScreen(),
    'home dashboard': () => const HomeDashboardScreen(),
    'workspace hub': () => const WorkspaceHubScreen(),
    'review queue': () => const ReviewQueueScreen(),
    'brand check editor': () => const NewBrandCheckScreen(),
    'findings': () => FindingsEvidenceScreen(
      contentText: 'Acme coffee is the best in the world.',
      onContentUpdated: (_) {},
      checkId: 'check-test',
      brandName: 'Acme',
      status: 'review_required',
      findings: const [
        {
          'rule_id': 'BG-002',
          'severity': 'warning',
          'message': 'Unapproved superlative detected.',
          'evidence': 'best in the world',
        },
      ],
    ),
    'guidelines hub': () => const GuidelinesHubScreen(),
    'analytics': () => const AnalyticsScreen(),
    'profile': () => const ProfileScreen(),
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppearanceController.instance.setMode(AppearanceMode.light);
    session.signIn(DemoAuth.reviewer.user, accessToken: 'test-access');
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/analytics') {
        return http.Response(
          '{"total_checks":9,"pending":5,"approved":2,"rejected":2,'
          '"total_findings":7,"scan_passed":6}',
          200,
        );
      }
      if (path == '/api/v1/auth/config') {
        return http.Response(
          '{"auth_provider":"supabase","demo_accounts_enabled":false,'
          '"email_reset_available":true}',
          200,
        );
      }
      return http.Response(
        '{"items":[],"total":0,"reviews":[],"events":[],"receipts":[],'
        '"unread":0,"auth_provider":"supabase","database":"postgres"}',
        200,
      );
    });
  });

  tearDown(() {
    session.signOut();
    AppearanceController.instance.setMode(AppearanceMode.light);
  });

  test('controller resolves light, dark and system correctly', () {
    final controller = AppearanceController.instance;
    controller.setMode(AppearanceMode.light);
    controller.updateSystemBrightness(true);
    expect(controller.isDark, isFalse, reason: 'explicit light wins');

    controller.setMode(AppearanceMode.dark);
    controller.updateSystemBrightness(false);
    expect(controller.isDark, isTrue, reason: 'explicit dark wins');

    controller.setMode(AppearanceMode.system);
    controller.updateSystemBrightness(true);
    expect(controller.isDark, isTrue, reason: 'system follows dark device');
    controller.updateSystemBrightness(false);
    expect(controller.isDark, isFalse, reason: 'system follows light device');
  });

  test('preference values round-trip and unknown input falls back', () {
    expect(AppearanceController.parse('light'), AppearanceMode.light);
    expect(AppearanceController.parse('dark'), AppearanceMode.dark);
    expect(AppearanceController.parse('system'), AppearanceMode.system);
    expect(AppearanceController.parse(null), AppearanceMode.system);
    expect(AppearanceController.parse('neon'), AppearanceMode.system);
  });

  for (final brightness in Brightness.values) {
    final isDark = brightness == Brightness.dark;
    testWidgets(
      'all screens build cleanly in ${isDark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final problems = <String>[];

        for (final entry in screens.entries) {
          AppTheme.syncBrightness(brightness);
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: isDark ? AppTheme.dark : AppTheme.light,
              home: entry.value(),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          final error = tester.takeException();
          if (error != null) {
            problems.add('${entry.key}: ${error.toString().split('\n').first}');
            await tester.pumpWidget(const SizedBox.shrink());
            tester.takeException();
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
        AppTheme.syncBrightness(Brightness.light);
      },
    );
  }

  testWidgets('dark theme actually paints dark surfaces with light text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    AppTheme.syncBrightness(Brightness.dark);
    expect(AppTheme.background.computeLuminance(), lessThan(0.1));
    expect(AppTheme.card.computeLuminance(), lessThan(0.2));
    expect(AppTheme.ink.computeLuminance(), greaterThan(0.6));
    expect(AppTheme.inkStrong.computeLuminance(), greaterThan(0.7));
    expect(AppTheme.muted.computeLuminance(), greaterThan(0.3));
    for (final pair in [
      (AppTheme.success, AppTheme.successBg),
      (AppTheme.warning, AppTheme.warningBg),
      (AppTheme.danger, AppTheme.dangerBg),
      (AppTheme.info, AppTheme.infoBg),
    ]) {
      final contrast =
          (pair.$1.computeLuminance() + 0.05) /
          (pair.$2.computeLuminance() + 0.05);
      expect(
        contrast,
        greaterThan(4.0),
        reason: 'feedback colour contrast on dark background',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: HomeDashboardScreen(embedded: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    // Every card on the screen must be dark — one light card is the bug we
    // just spent a browser round chasing.
    final cards = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(SurfaceCard),
        matching: find.byType(Material),
      ),
    );
    expect(cards, isNotEmpty);
    final light = cards
        .map((c) => c.color)
        .where((c) => c != null && c.computeLuminance() > 0.4)
        .toList();
    expect(
      light,
      isEmpty,
      reason:
          '${light.length} SurfaceCards still paint a light colour in dark '
          'mode: $light',
    );
    AppTheme.syncBrightness(Brightness.light);
  });

  testWidgets('profile selector switches appearance and persists the value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = AppearanceController.instance;
    controller.setMode(AppearanceMode.light);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // The appearance card lives below the fold: scroll it into view first.
    final listView = find.byType(ListView);
    for (var i = 0; i < 12; i++) {
      await tester.drag(listView.first, const Offset(0, -280));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 200));
    // The pill mirrors the active mode, so each option label is unique when
    // the selector is showing the previous one.
    final darkChip = find.text('Dark');
    expect(darkChip, findsOneWidget);

    await tester.tap(darkChip);
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.mode, AppearanceMode.dark);
    expect(controller.storageValue, 'dark');

    await tester.tap(find.text('System'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.mode, AppearanceMode.system);
    expect(controller.storageValue, 'system');

    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.mode, AppearanceMode.light);
    expect(controller.storageValue, 'light');
    expect(tester.takeException(), isNull);
  });
}
