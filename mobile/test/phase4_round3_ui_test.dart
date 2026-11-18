import 'dart:convert';

import 'package:brandguard/app/app_theme.dart';
import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:brandguard/features/approvals/approval_verification_screen.dart';
import 'package:brandguard/features/checks/findings_evidence_screen.dart';
import 'package:brandguard/features/checks/new_brand_check_screen.dart';
import 'package:brandguard/features/governance/clarity_tickets_screen.dart';
import 'package:brandguard/features/governance/conflicts_screen.dart';
import 'package:brandguard/features/guidelines/fact_sources_screen.dart';
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

      expect(find.text('Queued as v1 · Done'), findsOneWidget);
      expect(versionCalls, 0);

      await scrollAndEnsure(tester, find.text('Apply suggestion'));
      await tester.tap(find.text('Apply suggestion'));
      await settleTestUi(tester);
      ScaffoldMessenger.of(
        tester.element(find.byType(FindingsEvidenceScreen)),
      ).clearSnackBars();
      await settleTestUi(tester);

      expect(find.text('Submit edited v2 for review'), findsOneWidget);
      await tester.tap(find.text('Submit edited v2 for review'));
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
        'approval verify': () => const ApprovalVerificationScreen(),
        'review queue': () => const ReviewQueueScreen(),
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
}
