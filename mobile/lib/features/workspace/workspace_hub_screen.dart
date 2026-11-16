import 'package:material_ui/material_ui.dart';

import '../checks/new_brand_check_screen.dart';
import '../drafts/drafts_screen.dart';
import '../reviews/review_queue_screen.dart';
import '../approvals/approval_verification_screen.dart';
import '../guidelines/brand_guidelines_screen.dart';
import '../guidelines/upload_rule_screen.dart';
import '../guidelines/fact_sources_screen.dart';
import '../analytics/analytics_screen.dart';
import 'server_records_screen.dart';

class WorkspaceHubScreen extends StatelessWidget {
  const WorkspaceHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData, Widget)>[
      (
        'New Brand Check',
        'Run the current backend checks on your exact text.',
        Icons.shield_outlined,
        const NewBrandCheckScreen(),
      ),
      (
        'Saved Drafts',
        'Continue a private, server-stored draft.',
        Icons.edit_note,
        const DraftsScreen(),
      ),
      (
        'Review Queue',
        'Inspect submissions and record reviewer decisions.',
        Icons.assignment_turned_in_outlined,
        const ReviewQueueScreen(),
      ),
      (
        'Verify Approval',
        'Compare an approval with exact text and current rules.',
        Icons.verified_user_outlined,
        const ApprovalVerificationScreen(),
      ),
      (
        'Brand Guidelines',
        'Read shared guidance; reviewers can edit it.',
        Icons.menu_book_outlined,
        const BrandGuidelinesScreen(),
      ),
      (
        'Enforceable Rules',
        'Manage the versioned rules used by the API.',
        Icons.rule,
        const UploadRuleScreen(),
      ),
      (
        'Fact Sources',
        'Ingest documents and verify eligible evidence.',
        Icons.fact_check_outlined,
        const FactSourcesScreen(),
      ),
      (
        'Analytics & Reports',
        'Current backend totals, scoped to your identity.',
        Icons.analytics_outlined,
        const AnalyticsScreen(),
      ),
      (
        'Version History',
        'Stored versions of accessible submissions.',
        Icons.history,
        const ServerRecordsScreen(kind: 'history', title: 'Version History'),
      ),
      (
        'Audit Ledger',
        'Actual governance events stored by the backend.',
        Icons.policy_outlined,
        const ServerRecordsScreen(kind: 'audit', title: 'Audit Ledger'),
      ),
      (
        'Processing Receipts',
        'Protected receipts for accessible submissions.',
        Icons.receipt_long_outlined,
        const ServerRecordsScreen(
          kind: 'receipts',
          title: 'Processing Receipts',
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF142C3B),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.layers_outlined, size: 36, color: Color(0xFF81F7E1)),
                SizedBox(height: 12),
                Text(
                  'Brand Governance Workspace',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Live checks, shared knowledge and an auditable review workflow.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => entry.$4),
                  ),
                  leading: Icon(entry.$3, color: const Color(0xFF006B5E)),
                  title: Text(
                    entry.$1,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(entry.$2),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
