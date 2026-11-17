import 'dart:convert';

import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/analytics/analytics_screen.dart';
import 'package:brandguard/features/approvals/approval_verification_screen.dart';
import 'package:brandguard/features/auth/create_account_screen.dart';
import 'package:brandguard/features/auth/forgot_password_screen.dart';
import 'package:brandguard/features/auth/sign_in_screen.dart';
import 'package:brandguard/features/checks/findings_evidence_screen.dart';
import 'package:brandguard/features/checks/new_brand_check_screen.dart';
import 'package:brandguard/features/dashboard/home_dashboard_screen.dart';
import 'package:brandguard/features/drafts/drafts_screen.dart';
import 'package:brandguard/features/guidelines/brand_guidelines_screen.dart';
import 'package:brandguard/features/guidelines/fact_sources_screen.dart';
import 'package:brandguard/features/guidelines/guidelines_hub_screen.dart';
import 'package:brandguard/features/guidelines/library_screen.dart';
import 'package:brandguard/features/guidelines/upload_rule_screen.dart';
import 'package:brandguard/features/notifications/notifications_screen.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
import 'package:brandguard/features/receipts/receipt_detail_screen.dart';
import 'package:brandguard/features/reviews/review_queue_screen.dart';
import 'package:brandguard/features/splash/splash_screen.dart';
import 'package:brandguard/features/workspace/server_records_screen.dart';
import 'package:brandguard/features/workspace/workspace_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget_test_setup.dart';

/// Layout hardening sweep.
///
/// Every user-visible screen is pumped at small, standard and tablet widths,
/// with normal, large and very large system text. Any RenderFlex overflow,
/// assertion or paint error surfaces through [WidgetTester.takeException] and
/// fails the test — this is the automated guard against a "red screen".
void main() {
  configureTestFonts();

  // Worst cases only: the narrowest phone, the tallest aspect, a standard phone
  // and a tablet — combined with normal, large and very large system text.
  // `flutter test --dart-define=EXHAUSTIVE_LAYOUT=true` runs every size and
  // every text scale. The default keeps the suite fast enough to run on every
  // change while still covering the worst cases (narrow phone + large text).
  const exhaustive = bool.fromEnvironment('EXHAUSTIVE_LAYOUT');
  // Both appearances are swept: a dark-only regression (invisible text, a
  // hardcoded white panel) is exactly as fatal as a red screen.
  const appearances = <Brightness>[Brightness.light, Brightness.dark];
  const sizes = <Size>[
    Size(280, 600), // extreme narrow guard (older/small devices)
    Size(320, 568), // iPhone SE (1st gen)
    Size(360, 780),
    Size(430, 932),
    Size(768, 1024), // tablet
  ];
  // Default (fast) mode: the single worst case — the narrowest phone with the
  // largest system text — for every screen, both roles and all three backends.
  // `--dart-define=EXHAUSTIVE_LAYOUT=true` sweeps every size and scale.
  final activeSizes = exhaustive ? sizes : const [Size(280, 600)];
  const scales = <double>[1.0, 1.3, 1.6];
  final activeScales = exhaustive ? scales : const <double>[1.0, 1.6];

  final screens = <String, Widget Function()>{
    'splash': () => const SplashScreen(),
    'sign in': () => const SignInScreen(),
    'create account': () => const CreateAccountScreen(),
    'forgot password': () => const ForgotPasswordScreen(),
    'home dashboard': () => const HomeDashboardScreen(),
    'workspace hub': () => const WorkspaceHubScreen(),
    'review queue': () => const ReviewQueueScreen(),
    'brand check editor': () => const NewBrandCheckScreen(),
    'findings & evidence': () => FindingsEvidenceScreen(
      contentText: 'Acme coffee is the best in the world, buy now.',
      onContentUpdated: (_) {},
      checkId: 'check-test',
      brandName: 'Acme',
      status: 'review_required',
      findings: const [
        {
          'rule_id': 'BG-002',
          'severity': 'warning',
          'message': 'Unapproved superlative detected in the claim.',
          'evidence': 'best in the world',
          'suggestion': 'Use a verifiable claim instead.',
        },
      ],
    ),
    'approval verification': () => const ApprovalVerificationScreen(),
    'protected receipt': () =>
        const ReceiptDetailScreen(receiptId: 'receipt-test'),
    'brand guidelines': () => const BrandGuidelinesScreen(),
    'public library': () =>
        const LibraryScreen(kind: 'guidelines', title: 'Brand Guidelines'),
    'rule library': () => const UploadRuleScreen(),
    'fact sources': () => const FactSourcesScreen(),
    'notifications': () => const NotificationsScreen(),
    'profile': () => const ProfileScreen(),
    'analytics': () => const AnalyticsScreen(),
    'saved drafts': () => const DraftsScreen(),
    'version history': () =>
        const ServerRecordsScreen(kind: 'history', title: 'Version History'),
    'audit ledger': () =>
        const ServerRecordsScreen(kind: 'audit', title: 'Audit Ledger'),
    'processing receipts': () => const ServerRecordsScreen(
      kind: 'receipts',
      title: 'Processing Receipts',
    ),
    'guidelines hub': () => const GuidelinesHubScreen(),
    'embedded home': () => const HomeDashboardScreen(embedded: true),
    'embedded workspace': () => const WorkspaceHubScreen(embedded: true),
    'embedded reviews': () => const ReviewQueueScreen(embedded: true),
    'embedded guidelines': () => const GuidelinesHubScreen(embedded: true),
    'embedded profile': () => const ProfileScreen(embedded: true),
  };

  /// Three backends: healthy, empty, and hard failure — the states that
  /// actually break layouts in the field.
  final backends = <String, MockClient Function()>{
    'populated': () => MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/analytics') {
        return http.Response(
          jsonEncode({
            'total_checks': 128,
            'pending': 47,
            'approved': 61,
            'rejected': 20,
            'total_findings': 312,
            'scan_passed': 87,
            'rule_counts': {'BG-001': 12, 'BG-002': 9, 'BG-003': 4},
            'updated_at': '2026-11-15T10:00:00Z',
          }),
          200,
        );
      }
      if (path == '/api/v1/system/status') {
        return http.Response(
          jsonEncode({
            'auth_provider': 'supabase',
            'database': 'postgres',
            'ai_configured': false,
            'storage_bucket': 'brandguard-files',
          }),
          200,
        );
      }
      if (path == '/api/v1/notifications') {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'n1',
                'title': 'A very long notification title that keeps going to test wrapping behaviour',
                'body': 'A deliberately long body message describing an approval decision recorded for a brand check with an extremely verbose explanation of what happened next.',
                'created_at': '2026-11-15T10:00:00Z',
                'read': false,
              },
              {
                'id': 'n2',
                'title': 'Decision recorded',
                'body': 'Approved exact content',
                'created_at': '2026-11-14T09:00:00Z',
                'read': true,
              },
            ],
            'unread': 1,
          }),
          200,
        );
      }
      if (path.startsWith('/api/v1/reviews')) {
        return http.Response(
          jsonEncode({
            'reviews': [
              {
                'check_id': 'c1',
                'brand_name': 'Demo EcoSip',
                'creator_id': 'u1',
                'status': 'pending',
                'content_version': 1,
                'rules_version': '1.0.1',
                'created_at': '2026-11-15T10:00:00Z',
                'content': 'A long piece of marketing copy used to verify that the review sheet scrolls and wraps correctly at every width.',
                'content_hash': 'bf57aba80a43e4dc85a1b6f0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0',
                'findings': [
                  {'rule_id': 'BG-002', 'severity': 'warning'},
                ],
              },
            ],
            'total': 1,
          }),
          200,
        );
      }
      if (path.startsWith('/api/v1/receipts')) {
        return http.Response(
          jsonEncode({
            'receipt_id': 'receipt-test',
            'check_id': 'c1',
            'brand_name': 'Demo EcoSip',
            'content_hash': 'bf57aba80a43e4dc85a1b6f0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0',
            'content_version': 3,
            'rules_version': '1.0.1',
            'status': 'approved',
            'deterministic_findings': [
              {
                'rule_id': 'BG-002',
                'message': 'Superlative claim needs proof.',
              },
            ],
            'ai_verification': {
              'status': 'abstained',
              'message': 'AI verification is disabled on this deployment.',
            },
            'created_at': '2026-11-15T10:00:00Z',
          }),
          200,
        );
      }
      if (path.startsWith('/api/v1/library/')) {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'lib-1',
                'title': 'An intentionally long library entry title to force multi-line wrapping inside a card',
                'body': 'Long body text that describes a guideline in enough detail to wrap across several lines on the narrowest supported phone width.',
                'status': 'active',
                'version': '1.0.1',
                'pattern': r'\bfree forever\b',
                'verified': true,
              },
            ],
            'total': 1,
          }),
          200,
        );
      }
      if (path.startsWith('/api/v1/drafts')) {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'd1',
                'title': 'A very long draft title that must wrap or truncate gracefully',
                'brand_name': 'Demo NutriLeaf',
                'revision': 7,
                'updated_at': '2026-11-15T10:00:00Z',
                'content': 'Draft body',
              },
            ],
            'total': 1,
          }),
          200,
        );
      }
      if (path.startsWith('/api/v1/history') ||
          path.startsWith('/api/v1/audit') ||
          path.startsWith('/api/v1/versions')) {
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'h1',
                'check_id': 'c1',
                'event': 'review_decision',
                'status': 'approved',
                'version': 'v1',
                'created_at': '2026-11-15T10:00:00Z',
                'actor': 'reviewer@example.com',
                'detail': 'Approved with the exact stored hash.',
              },
            ],
            'total': 1,
          }),
          200,
        );
      }
      if (path == '/api/v1/auth/config') {
        return http.Response(
          jsonEncode({
            'auth_provider': 'supabase',
            'demo_accounts_enabled': false,
            'email_reset_available': true,
          }),
          200,
        );
      }
      return http.Response(
        '{"items":[],"total":0,"reviews":[],"events":[],"receipts":[],"unread":0}',
        200,
      );
    }),
    'empty': () => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/config') {
        return http.Response(
          '{"auth_provider":"local","demo_accounts_enabled":true,"email_reset_available":false}',
          200,
        );
      }
      if (request.url.path == '/api/v1/system/status') {
        return http.Response(
          '{"auth_provider":"local","database":"sqlite"}',
          200,
        );
      }
      return http.Response(
        '{"items":[],"total":0,"reviews":[],"events":[],"receipts":[],"unread":0,'
        '"total_checks":0,"pending":0,"approved":0,"rejected":0,"total_findings":0}',
        200,
      );
    }),
    'broken': () => MockClient((request) async {
      if (request.url.path == '/api/v1/auth/config') {
        return http.Response(
          '{"auth_provider":"local","demo_accounts_enabled":false,"email_reset_available":false}',
          200,
        );
      }
      return http.Response(
        '{"detail":"Upstream governance store unavailable"}',
        503,
      );
    }),
  };

  for (final backend in backends.entries) {
    for (final scale in activeScales) {
      for (final appearance in appearances) {
        testWidgets(
          'every screen lays out cleanly with ${backend.key} data at text scale $scale '
          '(${appearance == Brightness.dark ? 'dark' : 'light'})',
          timeout: const Timeout(Duration(minutes: 5)),
          (tester) async {
            final problems = <String>[];
            SharedPreferences.setMockInitialValues({});
            BrandGuardApiService.clientForTesting = backend.value();
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            for (final reviewer in const [false, true]) {
              session.signIn(
                reviewer ? DemoAuth.reviewer.user : DemoAuth.creator.user,
                accessToken: 'test-access',
              );
              for (final entry in screens.entries) {
                for (final size in activeSizes) {
                  tester.view.physicalSize = size;
                  tester.view.devicePixelRatio = 1;
                  // Unmount the previous screen first: timers and pending
                  // futures from a failing request would otherwise leak into the
                  // next screen and stall the whole sweep.
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pump();
                  tester.takeException();
                  AppTheme.syncBrightness(appearance);
                  await tester.pumpWidget(
                    MaterialApp(
                      key: UniqueKey(),
                      theme: appearance == Brightness.dark
                          ? AppTheme.dark
                          : AppTheme.light,
                      home: entry.value(),
                      routes: {
                        '/receiptDetail': (_) => const ReceiptDetailScreen(
                          receiptId: 'receipt-test',
                        ),
                      },
                    ),
                  );
                  await tester.pump(const Duration(milliseconds: 400));
                  // Let any client-side retry/backoff timer fire; otherwise the
                  // pending timer keeps the binding busy forever.
                  await tester.pump(const Duration(seconds: 2));
                  // Collect instead of asserting immediately: one failing screen
                  // must not hide the rest of the report.
                  final error = tester.takeException();
                  if (error != null) {
                    problems.add(
                      '${entry.key} | ${backend.key} data | '
                      '${size.width.toInt()}x${size.height.toInt()} | '
                      'textScale $scale | '
                      '${reviewer ? 'reviewer' : 'creator'} | '
                      '${appearance == Brightness.dark ? 'dark' : 'light'} | '
                      '${error.toString().split('\n').first}',
                    );
                    // Recover so the next pump starts from a clean tree.
                    await tester.pumpWidget(const SizedBox.shrink());
                    await tester.pump();
                    tester.takeException();
                  }
                }
              }
              session.signOut();
            }
            expect(
              problems,
              isEmpty,
              reason:
                  'Layout problems (${problems.length}):\n'
                  '${problems.take(40).map((p) => '  - $p').join('\n')}',
            );
          },
        );
      }
    }
  }
}
