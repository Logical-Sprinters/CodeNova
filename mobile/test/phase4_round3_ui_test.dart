import 'dart:convert';

import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/app/ui/brandguard_shell.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/approvals/approval_verification_screen.dart';
import 'package:brandguard/features/checks/findings_evidence_screen.dart';
import 'package:brandguard/features/checks/new_brand_check_screen.dart';
import 'package:brandguard/features/dashboard/home_dashboard_screen.dart';
import 'package:brandguard/features/governance/clarity_tickets_screen.dart';
import 'package:brandguard/features/governance/conflicts_screen.dart';
import 'package:brandguard/features/guidelines/fact_sources_screen.dart';
import 'package:brandguard/features/guidelines/guidelines_hub_screen.dart';
import 'package:brandguard/features/notifications/notifications_screen.dart';
import 'package:brandguard/features/profile/profile_screen.dart';
import 'package:brandguard/features/reviews/review_queue_screen.dart';
import 'package:brandguard/features/workspace/workspace_hub_screen.dart';
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
  });

  tearDown(() {
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppTheme.syncBrightness(brightness);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: screen,
      ),
    );
    await settleTestUi(tester);
  }

  Future<void> scrollAndEnsure(
    WidgetTester tester,
    Finder finder, {
    double delta = 200,
  }) async {
    if (finder.evaluate().isEmpty) {
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final pos = state.position;
      for (final step in [delta, -delta]) {
        var hops = 0;
        while (finder.evaluate().isEmpty && hops < 40) {
          final next = (pos.pixels + step).clamp(
            pos.minScrollExtent,
            pos.maxScrollExtent,
          );
          if ((next - pos.pixels).abs() < 0.5) break;
          pos.jumpTo(next);
          await tester.pump();
          hops += 1;
        }
        if (finder.evaluate().isNotEmpty) break;
      }
    }
    await tester.ensureVisible(finder);
    await settleTestUi(tester);
  }

  testWidgets(
    'Shift-Left Live Rule Radar sends channel + check_at and applies 1-click fix',
    (tester) async {
      final preflightRequests = <Map<String, dynamic>>[];
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/brand/preflight') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          preflightRequests.add(body);
          final content = body['content']?.toString() ?? '';
          final hasBad = content.contains('best in the world');
          return http.Response(
            jsonEncode({
              'status': hasBad ? 'warnings_detected' : 'clean',
              'brand_name': 'Acme',
              'channel': body['channel'] ?? 'all',
              'check_at': body['check_at'] ?? '2026-11-18T00:00:00Z',
              'total_findings': hasBad ? 1 : 0,
              'elapsed_ms': 3.4,
              'conflicts': [],
              'findings': hasBad
                  ? [
                      {
                        'finding_id': 'pf-1',
                        'rule_id': 'BG-002',
                        'rule_version': '1.0.0',
                        'rule_quote': 'Avoid unverified superlatives.',
                        'severity': 'warning',
                        'message': 'Unsupported superlative phrase.',
                        'evidence': 'best in the world',
                        'start_index': content.indexOf('best in the world'),
                        'end_index':
                            content.indexOf('best in the world') + 17,
                        'replacement': 'verified quality',
                        'source_origin': 'caption',
                      },
                    ]
                  : [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const NewBrandCheckScreen());

      await scrollAndEnsure(tester, find.text('INSTAGRAM'));
      await tester.tap(find.text('INSTAGRAM'));
      await tester.pump();
      await scrollAndEnsure(tester, find.text('Oct 2026'));
      await tester.tap(find.text('Oct 2026'));
      await tester.pump();

      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('check-content')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Acme has the best in the world coffee.',
      );
      await tester.pump(const Duration(milliseconds: 650));
      await settleTestUi(tester);

      expect(preflightRequests, isNotEmpty);
      expect(preflightRequests.last['channel'], 'instagram');
      expect(preflightRequests.last['check_at'], '2026-10-15T12:00:00Z');

      await scrollAndEnsure(
        tester,
        find.textContaining('Avoid unverified superlatives.'),
      );
      expect(
        find.textContaining('Avoid unverified superlatives.'),
        findsOneWidget,
      );
      await scrollAndEnsure(tester, find.text('Apply fix: verified quality'));
      await tester.tap(find.text('Apply fix: verified quality'));
      await tester.pump(const Duration(milliseconds: 250));
      await settleTestUi(tester);

      await scrollAndEnsure(tester, find.text('Pre-flight clear'), delta: -200);
      expect(find.text('Pre-flight clear'), findsOneWidget);
      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('check-content')),
        delta: -200,
      );
      final editor = tester.widget<TextField>(
        find.byKey(const ValueKey('check-content')),
      );
      expect(editor.controller?.text, 'Acme has the verified quality coffee.');
    },
  );

  testWidgets(
    'FindingsEvidenceScreen displays verbatim rule_quote, visual palette evidence, OCR block, and submits coded override',
    (tester) async {
      String? overridePath;
      Map<String, dynamic>? overrideBody;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        overridePath = request.url.path;
        overrideBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'message': 'Finding overridden with coded reason.',
            'clarity_ticket': {'ticket_id': 't-1'},
          }),
          200,
        );
      });

      await open(
        tester,
        FindingsEvidenceScreen(
          contentText: 'Save with Acme today.',
          onContentUpdated: (_) {},
          checkId: 'check-99',
          brandName: 'Acme',
          status: 'review_required',
          ocrText: 'SALE 99% OFF',
          findings: const [
            {
              'finding_id': 'f-1',
              'rule_id': 'VIS-02',
              'rule_version': '1.0.0',
              'rule_quote': 'Visual assets must strictly conform to Acme palette.',
              'severity': 'warning',
              'message': 'Dominant banner color #FF00AA is off-palette.',
              'evidence': '#FF00AA',
              'start_index': 0,
              'end_index': 0,
              'source_origin': 'visual_palette',
              'visual_evidence': {
                'check': 'palette',
                'asset_name': 'banner.png',
                'detected_hex': '#FF00AA',
                'coverage_pct': 62.5,
                'allowed_hex_colors': ['#0F172A', '#FFFFFF'],
              },
            },
          ],
        ),
      );

      expect(find.text('IMAGE OCR TEXT FUSED INTO CHECK'), findsOneWidget);
      expect(find.text('SALE 99% OFF'), findsOneWidget);
      await scrollAndEnsure(tester, find.text('VERBATIM RULE QUOTE'));
      expect(find.text('VERBATIM RULE QUOTE'), findsOneWidget);
      expect(
        find.textContaining('Visual assets must strictly conform to Acme palette.'),
        findsOneWidget,
      );
      await scrollAndEnsure(
        tester,
        find.textContaining('Detected #FF00AA (62.5% coverage)'),
      );
      expect(find.textContaining('Detected #FF00AA (62.5% coverage)'), findsOneWidget);

      await scrollAndEnsure(
        tester,
        find.text('Override finding (coded reason)'),
      );
      await tester.tap(find.text('Override finding (coded reason)'));
      await settleTestUi(tester);

      await tester.ensureVisible(find.text('Channel exemption'));
      await tester.tap(find.text('Channel exemption'));
      await tester.pump();
      await tester.ensureVisible(find.text('Log override'));
      await tester.tap(find.text('Log override'));
      await settleTestUi(tester);

      expect(overridePath, '/api/v1/reviews/check-99/findings/f-1/override');
      expect(overrideBody?['reason_code'], 'CHANNEL_EXEMPTION');
      await scrollAndEnsure(
        tester,
        find.textContaining('OVERRIDDEN (CHANNEL_EXEMPTION)'),
        delta: -200,
      );
      expect(find.textContaining('OVERRIDDEN (CHANNEL_EXEMPTION)'), findsOneWidget);
    },
  );

  testWidgets(
    'FindingsEvidenceScreen shows conflict escalation card and calls resolveConflict',
    (tester) async {
      String? resolvedPath;
      Map<String, dynamic>? resolvedBody;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        resolvedPath = request.url.path;
        resolvedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'message': 'Conflict resolved and winning source pinned.',
            'updated_checks': [
              {'check_id': 'check-conf', 'status': 'pending'},
            ],
          }),
          200,
        );
      });

      await open(
        tester,
        FindingsEvidenceScreen(
          contentText: '20% discount today.',
          onContentUpdated: (_) {},
          checkId: 'check-conf',
          brandName: 'Acme',
          status: 'review_paused_conflict',
          findings: const [],
          conflicts: const [
            {
              'conflict_id': 'conf-1',
              'topic_key': 'discount_cap',
              'clauses': [
                {
                  'source_type': 'rule',
                  'source_id': 'BG-DISC-25',
                  'version': '1.0.0',
                  'title': 'Max 25% discount',
                  'canonical_value': '25%',
                  'excerpt': 'Discounts must not exceed 25%.',
                },
                {
                  'source_type': 'fact',
                  'source_id': 'fact-15',
                  'version': '1.0.0',
                  'title': 'Q4 Promo Cap',
                  'canonical_value': '15%',
                  'excerpt': 'Approved Q4 cap is 15%.',
                },
              ],
            },
          ],
        ),
      );

      expect(find.text('REVIEW PAUSED — INTERNAL RULE CONFLICT'), findsOneWidget);
      await scrollAndEnsure(tester, find.text('Resolve & Pin Active Rule'));
      await tester.tap(find.text('Resolve & Pin Active Rule'));
      await settleTestUi(tester);

      await tester.ensureVisible(find.text('Pin winner & recheck'));
      await tester.tap(find.text('Pin winner & recheck'));
      await settleTestUi(tester);

      expect(resolvedPath, '/api/v1/conflicts/conf-1/resolve');
      expect(resolvedBody?['winning_source_type'], 'rule');
      expect(resolvedBody?['winning_source_id'], 'BG-DISC-25');
    },
  );

  testWidgets(
    'ClarityTicketsScreen and ConflictsScreen list records and perform actions',
    (tester) async {
      String? ticketPatchPath;
      String? conflictResolvePath;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/clarity-tickets' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'ticket_id': 't-100',
                  'brand_name': 'Acme',
                  'rule_id': 'BG-002',
                  'rule_version': '1.0.0',
                  'channel': 'instagram',
                  'owner_id': 'u2',
                  'override_count': 3,
                  'status': 'open',
                  'reason_breakdown': {'AMBIGUOUS_RULE_TEXT': 2, 'CHANNEL_EXEMPTION': 1},
                },
              ],
              'total': 1,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/clarity-tickets/t-100' &&
            request.method == 'PATCH') {
          ticketPatchPath = request.url.path;
          return http.Response('{"ticket":{"status":"acknowledged"}}', 200);
        }
        if (request.url.path == '/api/v1/conflicts' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'conflict_id': 'c-200',
                  'brand_name': 'Acme',
                  'topic_key': 'warranty_years',
                  'status': 'open',
                  'clauses': [
                    {
                      'source_type': 'rule',
                      'source_id': 'R-WAR-2',
                      'version': '1.0.0',
                      'title': 'Two year warranty',
                      'canonical_value': '2 years',
                      'excerpt': 'State 2-year warranty.',
                    },
                    {
                      'source_type': 'fact',
                      'source_id': 'F-WAR-3',
                      'version': '1.0.0',
                      'title': 'Updated warranty spec',
                      'canonical_value': '3 years',
                      'excerpt': 'Warranty extended to 3 years.',
                    },
                  ],
                },
              ],
              'total': 1,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/conflicts/c-200/resolve' &&
            request.method == 'POST') {
          conflictResolvePath = request.url.path;
          return http.Response('{"message":"ok"}', 200);
        }
        return http.Response('{"items":[],"total":0}', 200);
      });

      await open(tester, const ClarityTicketsScreen());
      await scrollAndEnsure(
        tester,
        find.textContaining('Acme · 3 overrides (instagram)'),
      );
      expect(find.textContaining('Acme · 3 overrides (instagram)'), findsOneWidget);
      await scrollAndEnsure(tester, find.text('Acknowledge'));
      await tester.tap(find.text('Acknowledge'));
      await settleTestUi(tester);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await settleTestUi(tester);
      expect(ticketPatchPath, '/api/v1/clarity-tickets/t-100');

      await open(tester, const ConflictsScreen());
      await scrollAndEnsure(tester, find.textContaining('Topic: warranty_years'));
      expect(find.textContaining('Topic: warranty_years'), findsOneWidget);
      await scrollAndEnsure(tester, find.text('Resolve & pin active rule'));
      await tester.tap(find.text('Resolve & pin active rule'));
      await settleTestUi(tester);
      await tester.ensureVisible(find.text('Pin winner & recheck'));
      await tester.tap(find.text('Pin winner & recheck'));
      await settleTestUi(tester);
      expect(conflictResolvePath, '/api/v1/conflicts/c-200/resolve');
    },
  );

  testWidgets(
    'ApprovalVerificationScreen sends verify_at and renders tamper word diff',
    (tester) async {
      Map<String, dynamic>? sentBody;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'valid': false,
            'seal_status': 'VOIDED_TAMPERED',
            'reason': 'APPROVAL VOIDED - Post-Sign-Off Tampering Detected.',
            'diff_segments': [
              {'op': 'equal', 'approved_text': 'Price ', 'current_text': 'Price '},
              {'op': 'replace', 'approved_text': '10', 'current_text': '15'},
            ],
            'tampered_tokens': [
              {'op': 'replace', 'label': "'10' -> '15'"},
            ],
            'rule_changes': [],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await open(tester, const ApprovalVerificationScreen());
      await scrollAndEnsure(tester, find.byType(TextField).at(0));
      await tester.enterText(find.byType(TextField).at(0), 'check-seal-1');
      await scrollAndEnsure(tester, find.byType(TextField).at(2));
      await tester.enterText(find.byType(TextField).at(2), 'Price 15');
      await scrollAndEnsure(tester, find.text('Oct 2026'), delta: 150);
      await tester.tap(find.text('Oct 2026'));
      await tester.pump();
      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('verify-approval-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('verify-approval-submit')));
      await settleTestUi(tester);

      expect(sentBody?['verify_at'], '2026-10-15T12:00:00Z');
      await scrollAndEnsure(tester, find.text('VOIDED_TAMPERED'));
      expect(find.text('VOIDED_TAMPERED'), findsOneWidget);
      await scrollAndEnsure(tester, find.text('WORD-LEVEL TAMPER DIFF'));
      expect(find.text('WORD-LEVEL TAMPER DIFF'), findsOneWidget);
    },
  );

  testWidgets(
    'GuidelinesHub and WorkspaceHub navigate to ClarityTickets and Conflicts screens',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => http.Response('{"items":[],"total":0}', 200),
      );

      for (final target in <String, Type>{
        'Clarity Tickets': ClarityTicketsScreen,
        'Policy Conflicts': ConflictsScreen,
      }.entries) {
        await open(tester, const GuidelinesHubScreen());
        final tile = find.text(target.key);
        await scrollAndEnsure(tester, tile);
        await tester.tap(tile);
        await settleTestUi(tester);
        expect(find.byType(target.value), findsOneWidget);

        await open(tester, const WorkspaceHubScreen());
        final wsTile = find.text(target.key);
        await scrollAndEnsure(tester, wsTile);
        await tester.tap(wsTile);
        await settleTestUi(tester);
        expect(find.byType(target.value), findsOneWidget);
      }
    },
  );

  testWidgets(
    'ProfileScreen My profile opens full identity & session sheet with rename action',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/system/status') {
          return http.Response(
            '{"auth_provider":"local","database":"sqlite","ai_configured":false}',
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/preferences') {
          return http.Response(
            '{"email_updates":true,"review_activity":true,"product_news":false}',
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const ProfileScreen());
      await scrollAndEnsure(tester, find.text('My profile'));
      await tester.tap(find.text('My profile'));
      await settleTestUi(tester);

      expect(find.text('IDENTITY & SESSION DETAILS'), findsOneWidget);
      expect(find.text(DemoAuth.reviewer.user.email!), findsWidgets);
      expect(find.text(DemoAuth.reviewer.user.userId), findsOneWidget);
      expect(find.text('Authenticated'), findsOneWidget);

      await tester.tap(find.text('Edit display name').last);
      await settleTestUi(tester);
      expect(find.text('Full name'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settleTestUi(tester);
    },
  );

  testWidgets(
    'FindingsEvidenceScreen avoids duplicate v2 when unedited and submits v2 only after suggestion applied',
    (tester) async {
      var versionCalls = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/brand/check-101/versions') {
          versionCalls++;
          return http.Response(
            jsonEncode({
              'check_id': 'check-101',
              'receipt_id': 'rcpt-102',
              'status': 'pending',
              'content_version': 2,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      const content = 'Limited time free unlimited forever offer';
      await open(
        tester,
        FindingsEvidenceScreen(
          contentText: content,
          onContentUpdated: (_) {},
          checkId: 'check-101',
          brandName: 'Acme',
          status: 'review_required',
          reviewStatus: 'pending',
          contentVersion: 1,
          findings: const [
            {
              'finding_id': 'f-dup-1',
              'rule_id': 'BG-001',
              'rule_version': '1.0.0',
              'rule_quote': 'Avoid free unlimited claims.',
              'severity': 'critical',
              'message': 'Avoid unapproved free unlimited claims.',
              'evidence': 'free unlimited',
              'replacement': 'standard',
              'start_index': 13,
              'end_index': 27,
              'source_origin': 'caption',
            },
          ],
        ),
      );

      expect(find.text('Done · Submitted for review'), findsOneWidget);
      expect(versionCalls, 0);

      await scrollAndEnsure(tester, find.text('Apply suggestion'));
      await tester.tap(find.text('Apply suggestion'));
      await settleTestUi(tester);
      ScaffoldMessenger.of(
        tester.element(find.byType(FindingsEvidenceScreen)),
      ).clearSnackBars();
      await settleTestUi(tester);

      expect(find.text('Submit edited changes for review'), findsOneWidget);
      await tester.tap(find.text('Submit edited changes for review'));
      await settleTestUi(tester);

      expect(versionCalls, 1);
      expect(find.text('Submission processed'), findsWidgets);
      expect(find.text('rcpt-102'), findsOneWidget);
    },
  );

  testWidgets(
    'FactSourcesScreen provides 1-tap Verify source for AI action on unverified facts',
    (tester) async {
      Map<String, dynamic>? sentPut;
      var verifiedNow = false;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/library/facts' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'fact-9',
                  'title': 'Pricing PDF',
                  'brand_name': 'Acme',
                  'content': 'Acme Pro costs 49 dollars per month.',
                  'enabled': true,
                  'verified': verifiedNow,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/library/facts/fact-9' &&
            request.method == 'PUT') {
          sentPut = jsonDecode(request.body) as Map<String, dynamic>;
          verifiedNow = true;
          return http.Response(
            jsonEncode({'id': 'fact-9', 'verified': true}),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const FactSourcesScreen());
      await scrollAndEnsure(tester, find.text('Verify source for AI'));
      await tester.tap(find.text('Verify source for AI'));
      await settleTestUi(tester);

      expect(sentPut?['verified'], true);
      expect(find.text('Verify source for AI'), findsNothing);
    },
  );

  testWidgets(
    'FindingsEvidenceScreen explains abstained AI checks in plain English for first-time users',
    (tester) async {
      await open(
        tester,
        FindingsEvidenceScreen(
          contentText: 'Clean draft copy',
          onContentUpdated: (_) {},
          checkId: 'check-plain-1',
          brandName: 'Acme',
          status: 'review_required',
          contentVersion: 1,
          findings: const [],
          aiVerification: const {
            'status': 'abstained',
            'message': 'No verified evidence available.',
          },
        ),
      );

      expect(find.text('AI comparison: abstained'), findsOneWidget);
      expect(
        find.textContaining('your standard brand rule checks still ran'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Profile Password & sessions lets users update their password via PUT /api/v1/auth/password',
    (tester) async {
      Map<String, dynamic>? sentBody;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/system/status') {
          return http.Response(
            jsonEncode({'auth_provider': 'local', 'database': 'sqlite'}),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/preferences') {
          return http.Response('{}', 200);
        }
        if (request.url.path == '/api/v1/auth/password' &&
            request.method == 'PUT') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'updated': true}), 200);
        }
        if (request.url.path == '/api/v1/auth/config') {
          return http.Response(
            jsonEncode({
              'auth_provider': 'local',
              'demo_accounts_enabled': true,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const ProfileScreen());
      await scrollAndEnsure(tester, find.text('Password & sessions'));
      await tester.tap(find.text('Password & sessions'));
      await settleTestUi(tester);

      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'oldpass123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'newpass1234',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'newpass1234',
      );
      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('update-password-btn')),
      );
      await tester.tap(find.byKey(const ValueKey('update-password-btn')));
      await settleTestUi(tester);

      expect(sentBody?['current_password'], 'oldpass123');
      expect(sentBody?['password'], 'newpass1234');
      expect(session.accessToken, isNull);
    },
  );

  testWidgets(
    'Reviewer Request changes sends changes_requested and Creator can Edit & resubmit',
    (tester) async {
      Map<String, dynamic>? decisionPayload;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/reviews' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-rev-1',
                  'brand_name': 'Acme',
                  'creator_id': 'creator-99',
                  'status': 'pending',
                  'content_version': 1,
                  'rules_version': '1.0.0',
                  'created_at': '2026-11-18T10:00:00Z',
                  'content': 'Original copy',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/reviews/chk-rev-1/decision' &&
            request.method == 'PATCH') {
          decisionPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'updated': true}), 200);
        }
        return http.Response('{}', 200);
      });

      await open(tester, const ReviewQueueScreen());
      await scrollAndEnsure(tester, find.text('Acme Brand Check'));
      expect(find.text('SUBMISSION'), findsOneWidget);
      expect(find.text('V1'), findsNothing);

      await tester.tap(find.text('Acme Brand Check'));
      await settleTestUi(tester);
      await tester.tap(find.text('Request changes'));
      await settleTestUi(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Clarify billing terms',
      );
      await tester.tap(find.text('Confirm'));
      await settleTestUi(tester);

      expect(decisionPayload?['decision'], 'changes_requested');
      expect(decisionPayload?['note'], 'Clarify billing terms');

      // Now sign in as the creator and verify Edit & Resubmit flow.
      session.signIn(
        DemoAuth.creator.user,
        accessToken: 'creator-access',
        refreshToken: 'creator-refresh',
      );
      Map<String, dynamic>? resubmitPayload;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/reviews' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-edit-1',
                  'brand_name': 'Acme',
                  'creator_id': DemoAuth.creator.user.userId,
                  'status': 'changes_requested',
                  'review_note': 'Clarify billing terms',
                  'content_version': 1,
                  'rules_version': '1.0.0',
                  'created_at': '2026-11-18T10:00:00Z',
                  'content': 'Original copy',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/chk-edit-1/versions' &&
            request.method == 'POST') {
          resubmitPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'check_id': 'chk-edit-1',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'draft',
              'content_version': 2,
              'receipt_id': 'rcpt-edit-2',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/chk-edit-1/submit' &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'check_id': 'chk-edit-1',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'pending',
              'content_version': 2,
              'receipt_id': 'rcpt-edit-2',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(
        tester,
        const ReviewQueueScreen(initialTab: 'Changes Requested'),
      );
      await scrollAndEnsure(tester, find.text('Acme Brand Check').first);
      await tester.tap(find.text('Acme Brand Check').first);
      await settleTestUi(tester);
      expect(find.text('Changes requested by reviewer'), findsOneWidget);
      expect(find.text('Clarify billing terms'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('edit-resubmit-review')));
      await settleTestUi(tester);

      expect(find.text('Edit & resubmit check'), findsOneWidget);
      await scrollAndEnsure(tester, find.byKey(const ValueKey('check-content')));
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Billed 49 dollars monthly.',
      );
      await scrollAndEnsure(tester, find.byKey(const ValueKey('run-check')));
      await tester.tap(find.byKey(const ValueKey('run-check')));
      await settleTestUi(tester);

      expect(resubmitPayload?['content'], 'Billed 49 dollars monthly.');
      expect(resubmitPayload?['expected_version'], 1);
      expect(resubmitPayload?['submit_for_review'], false);

      expect(find.text('Submit for authorised review'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('submit-authorised-review')));
      await settleTestUi(tester);
      expect(find.text('Submission processed'), findsOneWidget);
      expect(find.text('Done · Submitted for review'), findsOneWidget);
    },
  );

  testWidgets(
    'BrandGuardShell and ReviewQueueScreen sync in real time when a new brand check is submitted',
    (tester) async {
      var pendingChecks = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/analytics') {
          return http.Response(
            jsonEncode({
              'total_checks': pendingChecks,
              'pending': pendingChecks,
              'approved': 0,
              'rejected': 0,
              'changes_requested': 0,
              'total_findings': 0,
              'scan_passed': pendingChecks,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/notifications') {
          return http.Response(jsonEncode({'items': [], 'unread': 0}), 200);
        }
        if (request.url.path == '/api/v1/system/status') {
          return http.Response(
            jsonEncode({'auth_provider': 'local', 'database': 'sqlite'}),
            200,
          );
        }
        if (request.url.path == '/api/v1/reviews') {
          return http.Response(
            jsonEncode({
              'reviews': pendingChecks == 0
                  ? []
                  : [
                      {
                        'check_id': 'chk-live-1',
                        'brand_name': 'Acme',
                        'creator_id': 'creator-1',
                        'status': 'pending',
                        'content_version': 1,
                        'rules_version': '1.0.0',
                        'created_at': '2026-11-18T10:00:00Z',
                        'content': 'Live synced check',
                        'findings': const [],
                      },
                    ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/check' &&
            request.method == 'POST') {
          pendingChecks = 1;
          return http.Response(
            jsonEncode({
              'check_id': 'chk-live-1',
              'brand_name': 'Acme',
              'status': 'scan_passed',
              'findings': const [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const BrandGuardShell());
      expect(find.text('Live synced check'), findsNothing);

      await BrandGuardApiService.checkBrand(
        brandName: 'Acme',
        content: 'Live synced check',
      );
      await settleTestUi(tester);

      await tester.tap(find.text('Reviews').last);
      await settleTestUi(tester);
      expect(find.text('Acme Brand Check'), findsOneWidget);
    },
  );

  testWidgets(
    'NewBrandCheckScreen displays drafter details, red 200k limit error, and requires explicit Submit for authorised review',
    (tester) async {
      Map<String, dynamic>? checkBody;
      var submitCalls = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/brand/check' &&
            request.method == 'POST') {
          checkBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'check_id': 'chk-two-step',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'draft',
              'content_version': 1,
              'receipt_id': 'rcpt-two-step',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/chk-two-step/submit' &&
            request.method == 'POST') {
          submitCalls++;
          return http.Response(
            jsonEncode({
              'check_id': 'chk-two-step',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'pending',
              'content_version': 1,
              'receipt_id': 'rcpt-two-step',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const NewBrandCheckScreen());
      expect(
        find.textContaining(
          'Drafted by ${DemoAuth.reviewer.user.name} · ${DemoAuth.reviewer.user.email}',
        ),
        findsOneWidget,
      );

      await scrollAndEnsure(tester, find.byKey(const ValueKey('check-content')));
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'x ' * 100003,
      );
      await settleTestUi(tester);
      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('char-limit-error')),
      );
      expect(find.byKey(const ValueKey('char-limit-error')), findsOneWidget);
      expect(
        find.textContaining('Text limit crossed: maximum 200000 characters'),
        findsOneWidget,
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(0);
      await settleTestUi(tester);
      await scrollAndEnsure(tester, find.byKey(const ValueKey('check-content')));
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Acme official campaign copy',
      );
      await settleTestUi(tester);
      expect(find.byKey(const ValueKey('char-limit-error')), findsNothing);

      await scrollAndEnsure(tester, find.byKey(const ValueKey('run-check')));
      await tester.tap(find.byKey(const ValueKey('run-check')));
      await settleTestUi(tester);

      expect(checkBody?['submit_for_review'], false);
      expect(submitCalls, 0);
      expect(find.text('Submit for authorised review'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('submit-authorised-review')));
      await settleTestUi(tester);

      expect(submitCalls, 1);
      expect(find.text('Submission processed'), findsOneWidget);
      expect(find.text('Done · Submitted for review'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('submission-done-to-reviews')));
      await settleTestUi(tester);
      expect(find.byType(ReviewQueueScreen), findsOneWidget);
    },
  );

  testWidgets(
    'NotificationsScreen splits Unseen and Seen and marks unseen notifications seen when opened',
    (tester) async {
      var patchCalls = 0;
      var unseenRead = false;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'n-new',
                  'title': 'Review awaiting',
                  'body': 'Acme submission awaits review.',
                  'created_at': '2026-11-19T05:00:00Z',
                  'read': unseenRead,
                  'check_id': 'chk-n1',
                },
                {
                  'id': 'n-old',
                  'title': 'Previous notice',
                  'body': 'Old decision already seen.',
                  'created_at': '2026-11-18T05:00:00Z',
                  'read': true,
                },
              ],
              'unread': unseenRead ? 0 : 1,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/notifications/n-new' &&
            request.method == 'PATCH') {
          patchCalls++;
          unseenRead = true;
          return http.Response(jsonEncode({'id': 'n-new', 'read': true}), 200);
        }
        if (request.url.path == '/api/v1/reviews' && request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-n1',
                  'brand_name': 'Acme',
                  'creator_id': 'u1',
                  'creator_name': 'Alice',
                  'creator_email': 'creator@brandguard.demo',
                  'status': 'pending',
                  'content_version': 1,
                  'created_at': '2026-11-19T05:00:00Z',
                  'content': 'Check copy',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const NotificationsScreen());
      expect(find.text('Unseen'), findsOneWidget);
      expect(find.text('Seen'), findsOneWidget);
      expect(find.text('Review awaiting'), findsOneWidget);

      await tester.tap(find.text('Review awaiting'));
      await settleTestUi(tester);

      expect(patchCalls, 1);
      expect(unseenRead, isTrue);
      expect(find.text('Authorised review'), findsOneWidget);
      expect(find.text('AUTHORED BY & TIMELINE'), findsOneWidget);
    },
  );

  testWidgets(
    'ReviewQueueScreen sorts newest brand checks first and shows creator name and email',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/reviews') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-older',
                  'brand_name': 'OlderBrand',
                  'creator_id': 'u1',
                  'creator_name': 'Older User',
                  'creator_email': 'older@example.com',
                  'status': 'pending',
                  'content_version': 1,
                  'created_at': '2026-11-18T08:00:00Z',
                  'updated_at': '2026-11-18T08:00:00Z',
                  'content': 'Older text',
                  'findings': const [],
                },
                {
                  'check_id': 'chk-newer',
                  'brand_name': 'NewerBrand',
                  'creator_id': 'u1',
                  'creator_name': 'Smeet Patel',
                  'creator_email': 'smeet@example.com',
                  'status': 'pending',
                  'content_version': 1,
                  'created_at': '2026-11-19T09:30:00Z',
                  'updated_at': '2026-11-19T09:30:00Z',
                  'check_at': '2026-11-19T09:30:05Z',
                  'content': 'Newer text',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      await open(tester, const ReviewQueueScreen(), size: const Size(430, 1400));
      await scrollAndEnsure(tester, find.text('OlderBrand Brand Check'));
      final newerY = tester.getTopLeft(find.text('NewerBrand Brand Check')).dy;
      final olderY = tester.getTopLeft(find.text('OlderBrand Brand Check')).dy;
      expect(newerY, lessThan(olderY));
      expect(
        find.text('Drafted by Smeet Patel · smeet@example.com'),
        findsOneWidget,
      );

      await tester.tap(find.text('NewerBrand Brand Check'));
      await settleTestUi(tester);
      expect(find.text('Smeet Patel'), findsOneWidget);
      expect(find.text('Smeet Patel (smeet@example.com)'), findsNothing);
      expect(find.text('smeet@example.com'), findsOneWidget);
      expect(find.text('Current rules (at submission)'), findsOneWidget);
    },
  );

  testWidgets(
    'Done after Submit for authorised review inside BrandGuardShell switches directly to Reviews tab',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/analytics') {
          return http.Response(
            '{"total_checks":1,"pending":1,"approved":0,"rejected":0,"total_findings":0,"scan_passed":1}',
            200,
          );
        }
        if (request.url.path == '/api/v1/reviews') {
          return http.Response(jsonEncode({'reviews': const []}), 200);
        }
        if (request.url.path == '/api/v1/brand/check') {
          return http.Response(
            jsonEncode({
              'check_id': 'chk-nav',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'draft',
              'content_version': 1,
              'receipt_id': 'rcpt-nav',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/chk-nav/submit') {
          return http.Response(
            jsonEncode({
              'check_id': 'chk-nav',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'pending',
              'content_version': 1,
              'receipt_id': 'rcpt-nav',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        return http.Response('{"items":[],"unread":0}', 200);
      });

      await open(tester, const BrandGuardShell());
      await scrollAndEnsure(tester, find.text('New Brand Check').first);
      await tester.tap(find.text('New Brand Check').first);
      await settleTestUi(tester);

      await scrollAndEnsure(tester, find.byKey(const ValueKey('check-content')));
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Acme launch copy',
      );
      await scrollAndEnsure(tester, find.byKey(const ValueKey('run-check')));
      await tester.tap(find.byKey(const ValueKey('run-check')));
      await settleTestUi(tester);

      await tester.tap(find.byKey(const ValueKey('submit-authorised-review')));
      await settleTestUi(tester);
      await tester.tap(find.byKey(const ValueKey('submission-done-to-reviews')));
      await settleTestUi(tester);

      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
        2,
      );
      expect(find.text('Authorised review queue'), findsOneWidget);
      expect(find.byType(NewBrandCheckScreen), findsNothing);
      expect(find.byType(FindingsEvidenceScreen), findsNothing);
    },
  );

  testWidgets(
    'Approved check owner can tap Edit as new check to create a linked check without mutating the approved seal',
    (tester) async {
      Map<String, dynamic>? checkBody;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/reviews') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-approved-1',
                  'brand_name': 'Acme',
                  'creator_id': DemoAuth.creator.userId,
                  'creator_name': DemoAuth.creator.name,
                  'creator_email': DemoAuth.creator.email,
                  'status': 'approved',
                  'content_version': 1,
                  'channel': 'instagram',
                  'created_at': '2026-11-18T10:00:00Z',
                  'updated_at': '2026-11-18T11:00:00Z',
                  'decided_at': '2026-11-18T11:00:00Z',
                  'reviewer': DemoAuth.reviewer.userId,
                  'reviewer_name': DemoAuth.reviewer.name,
                  'reviewer_email': DemoAuth.reviewer.email,
                  'review_note': 'Approved as written',
                  'content': 'Approved launch copy',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/brand/check' &&
            request.method == 'POST') {
          checkBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'check_id': 'chk-revised-2',
              'parent_check_id': 'chk-approved-1',
              'brand_name': 'Acme',
              'status': 'review_required',
              'review_status': 'draft',
              'content_version': 1,
              'receipt_id': 'rcpt-revised-2',
              'findings': const [],
              'conflicts': const [],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      session.signIn(
        DemoAuth.creator.user,
        accessToken: 'creator-access',
        refreshToken: 'creator-refresh',
      );
      await open(
        tester,
        const ReviewQueueScreen(initialTab: 'Approved'),
      );
      await scrollAndEnsure(tester, find.text('Acme Brand Check').first);
      await tester.tap(find.text('Acme Brand Check').first);
      await settleTestUi(tester);

      expect(
        find.byKey(const ValueKey('revise-approved-review')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('revise-approved-review')));
      await settleTestUi(tester);

      expect(find.text('New revision from approved check'), findsOneWidget);
      await scrollAndEnsure(tester, find.byKey(const ValueKey('check-content')));
      await tester.enterText(
        find.byKey(const ValueKey('check-content')),
        'Updated launch copy v2',
      );
      await scrollAndEnsure(tester, find.byKey(const ValueKey('run-check')));
      await tester.tap(find.byKey(const ValueKey('run-check')));
      await settleTestUi(tester);

      expect(checkBody?['parent_check_id'], 'chk-approved-1');
      expect(checkBody?['submit_for_review'], false);
      expect(find.text('Submit for authorised review'), findsOneWidget);
    },
  );

  testWidgets(
    'Phase 4 screens pass extreme narrow layout hardening (280x600 @ 1.6x) in light and dark mode',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/clarity-tickets') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'ticket_id': 't-hard',
                  'brand_name': 'Acme Long Brand Title',
                  'rule_id': 'BG-002',
                  'rule_version': '1.2.3',
                  'channel': 'instagram',
                  'owner_id': 'reviewer@example.com',
                  'override_count': 4,
                  'status': 'acknowledged',
                  'reason_breakdown': {'AMBIGUOUS_RULE_TEXT': 4},
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/conflicts') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'conflict_id': 'conf-hard',
                  'brand_name': 'Acme',
                  'topic_key': 'very_long_conflict_topic_identifier',
                  'status': 'open',
                  'clauses': [
                    {
                      'source_type': 'rule',
                      'source_id': 'BG-1',
                      'version': '1.0.0',
                      'title': 'Rule Clause A',
                      'canonical_value': '10%',
                      'excerpt': 'Clause A excerpt text.',
                    },
                    {
                      'source_type': 'fact',
                      'source_id': 'F-1',
                      'version': '1.0.0',
                      'title': 'Fact Clause B',
                      'canonical_value': '20%',
                      'excerpt': 'Clause B excerpt text.',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"items":[],"reviews":[],"total":0}', 200);
      });

      final round3Screens = <String, Widget Function()>{
        'clarity tickets': () => const ClarityTicketsScreen(),
        'conflicts': () => const ConflictsScreen(),
        'new brand check': () => const NewBrandCheckScreen(),
        'resubmit brand check': () => const NewBrandCheckScreen(
              resubmitCheckId: 'chk-1',
              expectedVersion: 1,
              initialBrandName: 'Acme',
              initialContent: 'Old claim text',
              reviewerNote: 'Clarify the monthly billing cadence clearly.',
              reviewStatus: 'Changes Requested',
            ),
        'approval verify': () => const ApprovalVerificationScreen(),
        'review queue': () => const ReviewQueueScreen(),
        'review queue changes': () =>
            const ReviewQueueScreen(initialTab: 'Changes Requested'),
        'findings conflict': () => FindingsEvidenceScreen(
              contentText: 'Promo copy',
              onContentUpdated: (_) {},
              checkId: 'chk-1',
              brandName: 'Acme',
              status: 'review_paused_conflict',
              findings: const [],
              conflicts: const [
                {
                  'conflict_id': 'c1',
                  'topic_key': 'cap',
                  'clauses': [
                    {
                      'source_type': 'rule',
                      'source_id': 'R1',
                      'version': '1.0.0',
                      'title': 'Rule',
                      'canonical_value': '10%',
                      'excerpt': 'Excerpt 1',
                    },
                  ],
                },
              ],
            ),
        'findings visual': () => FindingsEvidenceScreen(
              contentText: 'Promo copy',
              onContentUpdated: (_) {},
              checkId: 'chk-2',
              brandName: 'Acme',
              status: 'review_required',
              ocrText: 'OCR EXTRACTED TEXT',
              findings: const [
                {
                  'finding_id': 'f-v1',
                  'rule_id': 'VIS-02',
                  'rule_version': '1.0.0',
                  'rule_quote': 'Use brand palette only.',
                  'severity': 'warning',
                  'message': 'Off-palette color.',
                  'evidence': '#FF00AA',
                  'start_index': 0,
                  'end_index': 0,
                  'source_origin': 'visual_palette',
                  'visual_evidence': {
                    'check': 'palette',
                    'asset_name': 'banner.png',
                    'detected_hex': '#FF00AA',
                    'coverage_pct': 55.0,
                    'allowed_hex_colors': ['#0F172A', '#FFFFFF'],
                  },
                },
              ],
            ),
      };

      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final entry in round3Screens.entries) {
          await open(
            tester,
            entry.value(),
            size: const Size(280, 600),
            brightness: brightness,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} in $brightness at 280x600 @ 1.6x',
          );
        }
      }
    },
  );

  testWidgets(
    'Reviewer can amend an accidental rejection within grace window and sees expired-window notice after deadline',
    (tester) async {
      Map<String, dynamic>? amendBody;
      final futureDeadline = DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 45))
          .toIso8601String();
      final pastDeadline = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      var amended = false;

      BrandGuardApiService.clientForTesting = MockClient((request) async {
        if (request.url.path == '/api/v1/reviews') {
          return http.Response(
            jsonEncode({
              'reviews': [
                {
                  'check_id': 'chk-amend-1',
                  'brand_name': 'Acme',
                  'status': amended ? 'approved' : 'rejected',
                  'content_version': 1,
                  'creator_id': DemoAuth.creator.userId,
                  'creator_name': DemoAuth.creator.name,
                  'creator_email': DemoAuth.creator.email,
                  'created_at': '2026-11-18T10:00:00Z',
                  'decided_at': '2026-11-18T10:05:00Z',
                  'reviewer': DemoAuth.reviewer.userId,
                  'reviewer_name': DemoAuth.reviewer.name,
                  'reviewer_email': DemoAuth.reviewer.email,
                  'review_note': amended
                      ? 'Accidental tap reversed'
                      : 'Misclicked reject',
                  'can_amend': true,
                  'amend_window_minutes': 60,
                  'amend_deadline': futureDeadline,
                  'amend_remaining_seconds': 2700,
                  'content': 'Launch promo copy',
                  'findings': const [],
                },
                {
                  'check_id': 'chk-amend-expired',
                  'brand_name': 'Globex',
                  'status': 'approved',
                  'content_version': 1,
                  'creator_id': DemoAuth.creator.userId,
                  'creator_name': DemoAuth.creator.name,
                  'creator_email': DemoAuth.creator.email,
                  'created_at': '2026-11-18T07:00:00Z',
                  'decided_at': '2026-11-18T07:05:00Z',
                  'reviewer': DemoAuth.reviewer.userId,
                  'reviewer_name': DemoAuth.reviewer.name,
                  'reviewer_email': DemoAuth.reviewer.email,
                  'review_note': 'Approved earlier',
                  'can_amend': false,
                  'amend_window_minutes': 60,
                  'amend_deadline': pastDeadline,
                  'amend_remaining_seconds': 0,
                  'content': 'Expired window copy',
                  'findings': const [],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/reviews/chk-amend-1/amend' &&
            request.method == 'POST') {
          amendBody = jsonDecode(request.body) as Map<String, dynamic>;
          amended = true;
          return http.Response(
            jsonEncode({
              'message': 'Decision amended from rejected to approved.',
              'previous_decision': 'rejected',
              'review': {
                'check_id': 'chk-amend-1',
                'brand_name': 'Acme',
                'status': 'approved',
                'content_version': 1,
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      session.signIn(
        DemoAuth.reviewer.user,
        accessToken: 'reviewer-access',
        refreshToken: 'reviewer-refresh',
      );
      await open(tester, const ReviewQueueScreen(initialTab: 'All'));

      // 1) Active grace window on accidentally rejected check: Amend decision works.
      await scrollAndEnsure(tester, find.text('Acme Brand Check').first);
      await tester.tap(find.text('Acme Brand Check').first);
      await settleTestUi(tester);

      expect(
        find.byKey(const ValueKey('amend-decision-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('amend-decision-button')));
      await settleTestUi(tester);

      await tester.enterText(
        find.byType(TextField).last,
        'Accidental tap reversed after verifying caption',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-amend-decision')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-amend-decision')));
      await settleTestUi(tester);

      expect(amendBody?['decision'], 'approved');
      expect(amendBody?['expected_version'], 1);
      expect(
        amendBody?['reason'],
        'Accidental tap reversed after verifying caption',
      );

      // 2) After amending to Approved (still within grace window), card button & sheet Revoke / amend work cleanly.
      await scrollAndEnsure(
        tester,
        find.byKey(const ValueKey('card-amend-chk-amend-1')),
      );
      await tester.tap(find.byKey(const ValueKey('card-amend-chk-amend-1')));
      await settleTestUi(tester);
      expect(find.text('Revoke / amend approval'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'Revoking approval to reject with reason',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-amend-decision')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-amend-decision')));
      await settleTestUi(tester);
      expect(amendBody?['decision'], 'rejected');

      // 3) Expired grace window shows closed notice and hides amend button.
      await scrollAndEnsure(tester, find.text('Globex Brand Check').first);
      await tester.tap(find.text('Globex Brand Check').first);
      await settleTestUi(tester);
      expect(find.text('Amendment window closed'), findsOneWidget);
      expect(find.byKey(const ValueKey('amend-decision-button')), findsNothing);
    },
  );

  testWidgets(
    'ProfileScreen and HomeDashboardScreen omit internal Connected Backend stack card and auth/db details',
    (tester) async {
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/system/status') {
          return http.Response(
            jsonEncode({
              'auth_provider': 'local',
              'database': 'sqlite',
              'ai_configured': false,
            }),
            200,
          );
        }
        if (path == '/api/v1/analytics') {
          return http.Response(
            jsonEncode({
              'total_checks': 0,
              'pending': 0,
              'approved': 0,
              'rejected': 0,
              'total_findings': 0,
              'scan_passed': 0,
            }),
            200,
          );
        }
        return http.Response('{"items":[],"unread":0}', 200);
      });

      await open(tester, const ProfileScreen());
      expect(find.text('CONNECTED BACKEND'), findsNothing);
      expect(find.text('Auth provider'), findsNothing);
      expect(find.text('Database'), findsNothing);
      expect(find.text('sqlite'), findsNothing);
      expect(find.text('App version'), findsNothing);

      await tester.tap(find.text('My profile'));
      await settleTestUi(tester);
      expect(find.text('Auth provider'), findsNothing);
      expect(find.text('Database'), findsNothing);

      await open(tester, const HomeDashboardScreen());
      expect(find.textContaining('Backend: sqlite'), findsNothing);
      expect(find.textContaining('auth: local'), findsNothing);
    },
  );
}
