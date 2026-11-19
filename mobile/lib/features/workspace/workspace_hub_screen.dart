import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../analytics/analytics_screen.dart';
import '../approvals/approval_verification_screen.dart';
import '../checks/new_brand_check_screen.dart';
import '../drafts/drafts_screen.dart';
import '../governance/clarity_tickets_screen.dart';
import '../governance/conflicts_screen.dart';
import '../guidelines/brand_guidelines_screen.dart';
import '../guidelines/fact_sources_screen.dart';
import '../guidelines/upload_rule_screen.dart';
import '../reviews/review_queue_screen.dart';
import '../notifications/notifications_screen.dart';
import 'server_records_screen.dart';

class WorkspaceHubScreen extends StatelessWidget {
  const WorkspaceHubScreen({super.key, this.embedded = false});

  final bool embedded;

  static Future<void> _push(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final isReviewer = session.currentUser?.isReviewer == true;
    final groups = <(String, String, List<(String, String, IconData, Widget)>)>[
      (
        'Produce & review',
        'Checks, drafts and decisions',
        [
          (
            'New Brand Check',
            'Run the current backend checks on your exact text.',
            Icons.shield_outlined,
            const NewBrandCheckScreen(),
          ),
          (
            'Saved Drafts',
            'Continue a private, server-stored, versioned draft.',
            Icons.edit_note_rounded,
            const DraftsScreen(),
          ),
          (
            'Review Queue',
            isReviewer
                ? 'Inspect submissions and record reviewer decisions.'
                : 'Track submissions, view reviewer feedback & resubmit changes.',
            Icons.assignment_turned_in_outlined,
            const ReviewQueueScreen(),
          ),
          (
            'Verify Approval',
            'Compare an approval with exact text and current rules.',
            Icons.verified_user_outlined,
            const ApprovalVerificationScreen(),
          ),
        ],
      ),
      (
        'Governance library',
        'Shared knowledge and enforceable rules',
        [
          (
            'Brand Guidelines',
            'Read shared guidance; reviewers can edit it.',
            Icons.menu_book_outlined,
            const BrandGuidelinesScreen(),
          ),
          (
            'Enforceable Rules',
            'Manage the versioned rules used by the API.',
            Icons.rule_rounded,
            const UploadRuleScreen(),
          ),
          (
            'Fact Sources',
            'Ingest documents and verify eligible evidence.',
            Icons.fact_check_outlined,
            const FactSourcesScreen(),
          ),
          (
            'Clarity Tickets',
            'Review rule friction tickets opened by repeated coded overrides.',
            Icons.support_agent_rounded,
            const ClarityTicketsScreen(),
          ),
          (
            'Policy Conflicts',
            'Resolve contradictory rules or verified facts side-by-side.',
            Icons.balance_rounded,
            const ConflictsScreen(),
          ),
        ],
      ),
      (
        'Evidence & ledger',
        'Auditable records scoped to your role',
        [
          (
            'Analytics & Reports',
            'Current backend totals, scoped to your identity.',
            Icons.analytics_outlined,
            const AnalyticsScreen(),
          ),
          (
            'Version History',
            'Stored versions of accessible submissions.',
            Icons.history_rounded,
            const ServerRecordsScreen(
              kind: 'history',
              title: 'Version History',
            ),
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
        ],
      ),
    ];

    final content = RefreshIndicator(
      onRefresh: () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A3A4B), AppTheme.navyDeep],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.raisedShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.mintBright.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.layers_rounded,
                        size: 19,
                        color: AppTheme.mintBright,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Governance workspace',
                        style: AppTheme.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () {},
                      icon: Icon(
                        Icons.refresh,
                        color: AppTheme.mintBright,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Live checks, shared evidence and an auditable review workflow — every action runs against the connected backend.',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 12),
                // At large system text the chip alone can fill the row, so the
                // pair wraps instead of overflowing the hero card.
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RoleChip(isReviewer: isReviewer, onDark: true),
                    Text(
                      isReviewer
                          ? 'Can review and manage rules'
                          : 'Creator: own drafts and checks',
                      style: AppTheme.monoLabel(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            radius: 16,
            onTap: () => _push(context, const NotificationsScreen()),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: AppTheme.tealText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notifications & activity feed',
                    style: AppTheme.labelLarge.copyWith(fontSize: 13),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final group in groups) ...[
            const SizedBox(height: 14),
            SectionHeading(title: group.$1, caption: group.$2),
            const SizedBox(height: 8),
            for (final entry in group.$3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: EdgeInsets.zero,
                  radius: 16,
                  child: ListTile(
                    onTap: () => _push(context, entry.$4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.mint,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(entry.$3, size: 19, color: AppTheme.tealText),
                    ),
                    title: Text(
                      entry.$1,
                      style: AppTheme.labelLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(entry.$2, style: AppTheme.bodySmall),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    if (embedded) {
      return Column(
        children: [
          const ShellHeader(
            title: 'Workspace',
            subtitle: 'All governance modules',
          ),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Workspace'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _push(context, const NotificationsScreen()),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: SafeArea(top: false, child: content),
    );
  }
}
