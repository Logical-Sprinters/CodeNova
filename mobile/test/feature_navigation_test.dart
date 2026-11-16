import 'dart:async';
import 'dart:convert';

import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/approvals/approval_verification_screen.dart';
import 'package:brandguard/features/checks/findings_evidence_screen.dart';
import 'package:brandguard/features/checks/new_brand_check_screen.dart';
import 'package:brandguard/features/dashboard/home_dashboard_screen.dart';
import 'package:brandguard/features/analytics/analytics_screen.dart';
import 'package:brandguard/features/drafts/drafts_screen.dart';
import 'package:brandguard/features/guidelines/brand_guidelines_screen.dart';
import 'package:brandguard/features/guidelines/fact_sources_screen.dart';
import 'package:brandguard/features/guidelines/upload_rule_screen.dart';
import 'package:brandguard/features/notifications/notifications_screen.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
import 'package:brandguard/features/receipts/receipt_detail_screen.dart';
import 'package:brandguard/features/reviews/review_queue_screen.dart';
import 'package:brandguard/features/workspace/workspace_hub_screen.dart';
import 'package:brandguard/features/workspace/server_records_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/widget_test_setup.dart';

void main() {
  configureTestFonts();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    session.signIn(
      DemoAuth.reviewer.user,
      accessToken: 'reviewer-access',
      refreshToken: 'reviewer-refresh',
    );
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path == '/api/v1/analytics') {
        return http.Response(
          '{"total_checks":7,"pending":3,"approved":4,"rejected":0,"total_findings":2,"scan_passed":5,"rule_counts":{"BG-001":2},"updated_at":"2026-11-15"}',
          200,
        );
      }
      if (request.url.path == '/api/v1/system/status') {
        return http.Response(
          '{"auth_provider":"local","database":"sqlite","ai_configured":false}',
          200,
        );
      }
      if (request.url.path.startsWith('/api/v1/receipts/receipt-')) {
        return http.Response(
          '{"receipt_id":"receipt-test","ai_verification":{"status":"abstained"}}',
          200,
        );
      }
      return http.Response(
        '{"items":[],"total":0,"reviews":[],"events":[],"receipts":[],"unread":0}',
        200,
      );
    });
  });
  tearDown(() {
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });
  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.light,
        home: screen,
        routes: {
          '/receiptDetail': (_) =>
              const ReceiptDetailScreen(receiptId: 'receipt-test'),
        },
      ),
    );
    await settleTestUi(tester);
  }

  final screens = <String, Widget Function()>{
    'live dashboard': () => const HomeDashboardScreen(),
    'workspace': () => const WorkspaceHubScreen(),
    'review queue': () => const ReviewQueueScreen(),
    'brand check editor': () => const NewBrandCheckScreen(),
    'findings': () => FindingsEvidenceScreen(
      contentText: 'Announcement',
      onContentUpdated: (_) {},
      checkId: 'check-test',
      brandName: 'Acme',
      status: 'review_required',
      findings: const [],
    ),
    'approval verification': () => const ApprovalVerificationScreen(),
    'protected receipt': () =>
        const ReceiptDetailScreen(receiptId: 'receipt-test'),
    'shared guidelines': () => const BrandGuidelinesScreen(),
    'live rule library': () => const UploadRuleScreen(),
    'fact sources': () => const FactSourcesScreen(),
    'notifications': () => const NotificationsScreen(),
    'profile': () => const ProfileScreen(),
    'live analytics': () => const AnalyticsScreen(),
    'saved drafts': () => const DraftsScreen(),
    'stored version history': () =>
        const ServerRecordsScreen(kind: 'history', title: 'Version History'),
    'stored audit ledger': () =>
        const ServerRecordsScreen(kind: 'audit', title: 'Audit Ledger'),
    'stored receipts': () => const ServerRecordsScreen(
      kind: 'receipts',
      title: 'Processing Receipts',
    ),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} lays out at phone size', (tester) async {
      final screen = entry.value();
      await open(tester, screen);
      expect(find.byType(screen.runtimeType), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'workspace reaches every live feature, without sample screen fallbacks',
    (tester) async {
      final routes = <String, Type>{
        'New Brand Check': NewBrandCheckScreen,
        'Saved Drafts': DraftsScreen,
        'Review Queue': ReviewQueueScreen,
        'Verify Approval': ApprovalVerificationScreen,
        'Brand Guidelines': BrandGuidelinesScreen,
        'Enforceable Rules': UploadRuleScreen,
        'Fact Sources': FactSourcesScreen,
        'Analytics & Reports': AnalyticsScreen,
        'Version History': ServerRecordsScreen,
        'Audit Ledger': ServerRecordsScreen,
        'Processing Receipts': ServerRecordsScreen,
      };
      for (final entry in routes.entries) {
        await open(tester, const WorkspaceHubScreen());
        final tile = find.widgetWithText(ListTile, entry.key);
        await tester.scrollUntilVisible(tile, 200);
        await tester.tap(tile);
        await settleTestUi(tester);
        expect(find.byType(entry.value), findsOneWidget, reason: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
      }
    },
  );
  testWidgets('dashboard shows backend totals and explicit missing-AI status', (
    tester,
  ) async {
    await open(tester, const HomeDashboardScreen());
    expect(find.text('7'), findsOneWidget);
    expect(find.text('LIVE OVERVIEW'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('AI not configured:'),
      350,
    );
    expect(find.textContaining('AI not configured:'), findsOneWidget);
    expect(find.textContaining('SAMPLE OVERVIEW'), findsNothing);
  });
  testWidgets(
    'editor sends exact untrimmed content and displays real AI abstention',
    (tester) async {
      session.signIn(DemoAuth.creator.user, accessToken: 'creator-access');
      http.Request? submitted;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        submitted = request;
        return http.Response(
          jsonEncode({
            'check_id': 'check-created',
            'receipt_id': 'receipt-created',
            'brand_name': 'Acme',
            'status': 'review_required',
            'content_version': 1,
            'findings': [],
            'ai_verification': {
              'status': 'abstained',
              'message': 'No verified evidence available.',
            },
          }),
          200,
        );
      });
      await open(tester, const NewBrandCheckScreen());
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        '  Exact content\n',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('run-check')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('run-check')));
      await settleTestUi(tester);
      expect(submitted?.headers['Authorization'], 'Bearer creator-access');
      expect(jsonDecode(submitted!.body)['content'], '  Exact content\n');
      expect(find.byType(FindingsEvidenceScreen), findsOneWidget);
      expect(find.text('AI comparison: abstained'), findsOneWidget);
    },
  );
  testWidgets(
    'saved draft editor updates the same server id with revision protection',
    (tester) async {
      http.Request? saved;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        saved = request;
        return http.Response('{"id":"draft-one","revision":4}', 200);
      });
      await open(
        tester,
        const NewBrandCheckScreen(
          draft: {
            'id': 'draft-one',
            'revision': 3,
            'title': 'Campaign',
            'brand_name': 'Acme',
            'content': 'Original',
            'attachments': [],
          },
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Changed',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-draft')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('save-draft')));
      await settleTestUi(tester);
      expect(saved?.method, 'PUT');
      expect(saved?.url.path, '/api/v1/drafts/draft-one');
      expect(jsonDecode(saved!.body)['expected_revision'], 3);
      expect(
        find.text('Draft saved to the server (revision 4).'),
        findsOneWidget,
      );
    },
  );
  for (final reviewer in [false, true]) {
    testWidgets(
      reviewer
          ? 'reviewer can open library editor'
          : 'creator library is read-only',
      (tester) async {
        session.signIn(
          reviewer ? DemoAuth.reviewer.user : DemoAuth.creator.user,
          accessToken: 'access',
        );
        await open(tester, const BrandGuidelinesScreen());
        expect(
          find.byType(FloatingActionButton),
          reviewer ? findsOneWidget : findsNothing,
        );
        if (reviewer) {
          await tester.tap(find.byType(FloatingActionButton));
          await settleTestUi(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await settleTestUi(tester);
          expect(tester.takeException(), isNull);
        } else {
          expect(find.textContaining('Read-only:'), findsOneWidget);
        }
      },
    );
  }
  testWidgets(
    'notifications display actual backend notification and persist mark-read',
    (tester) async {
      var read = false;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.method == 'PATCH') {
          expect(request.url.path, '/api/v1/notifications/n1');
          read = true;
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'n1',
                'title': 'Decision recorded',
                'body': 'Approved exact content',
                'created_at': '2026-11-15',
                'read': read,
              },
            ],
          }),
          200,
        );
      });
      await open(tester, const NotificationsScreen());
      await tester.tap(find.text('Decision recorded'));
      await settleTestUi(tester);
      expect(read, isTrue);
    },
  );
  testWidgets('receipt response after dispose is ignored safely', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    BrandGuardApiService.clientForTesting = MockClient((_) => gate.future);
    await tester.pumpWidget(
      const MaterialApp(home: ReceiptDetailScreen(receiptId: 'slow')),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(http.Response('{}', 200));
    await settleTestUi(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'source citations show verbatim quotes rather than invented references',
    (tester) async {
      await open(
        tester,
        FindingsEvidenceScreen(
          contentText: 'Acme costs 10 dollars',
          onContentUpdated: (_) {},
          checkId: 'c',
          brandName: 'Acme',
          status: 'review_required',
          findings: const [],
          aiVerification: const {
            'status': 'needs_review',
            'message': 'Compare the price.',
            'citations': [
              {'title': 'Pricing source', 'quote': '49 dollars per month'},
            ],
          },
        ),
      );
      expect(find.textContaining('49 dollars per month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
