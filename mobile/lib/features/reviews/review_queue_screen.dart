import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  String selectedTab = 'Pending';

  List<Map<String, dynamic>> _backendReviews = [];
  bool isLoading = true;
  String? loadError;

  List<Map<String, dynamic>> get reviews => _backendReviews;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    if (!isLoading) setState(() => isLoading = true);
    try {
      final result = await _reviewsWithRetry();

      final List<dynamic> records = result['reviews'] ?? [];

      final mappedReviews = records.map((item) {
        final review = Map<String, dynamic>.from(item);

        final findings = (review['findings'] as List?) ?? [];

        final createdAt = DateTime.tryParse(
          review['created_at']?.toString() ?? '',
        );

        final severityLevels = findings
            .map((f) => f['severity']?.toString().toLowerCase())
            .toList();

        final risk =
            severityLevels.contains('critical') ||
                severityLevels.contains('review')
            ? 'High'
            : severityLevels.isNotEmpty
            ? 'Medium'
            : 'Low';

        final rawStatus = review['status']?.toString() ?? 'pending';

        return <String, dynamic>{
          'id': review['check_id']?.toString() ?? '',
          'title': '${review['brand_name'] ?? 'Unknown'} Brand Check',
          'creator': review['creator_id']?.toString() ?? 'Unknown',
          'channel': 'Text',
          'date': createdAt == null
              ? 'Unknown'
              : '${createdAt.day.toString().padLeft(2, '0')} '
                    '${createdAt.month.toString().padLeft(2, '0')} '
                    '${createdAt.year}',
          'status': rawStatus == 'approved'
              ? 'Approved'
              : rawStatus == 'rejected'
              ? 'Rejected'
              : rawStatus == 'pending_review' || rawStatus == 'pending'
              ? 'Pending'
              : rawStatus == 'completed'
              ? 'Completed'
              : 'Pending',
          'findings': findings.length,
          'version': 'v${review['content_version'] ?? 1}',
          'contentVersion': review['content_version'] as int?,
          'creatorId': review['creator_id'],
          'contentText': review['content']?.toString() ?? '',
          'rulesVersion': review['rules_version']?.toString() ?? 'Base rules',
          'risk': risk,
          'description':
              'Automated brand compliance check for ${review['brand_name']}. '
              'This review contains ${findings.length} detected findings.',
          'decisionBy': review['reviewer'],
          'decisionReason': review['review_note'],
          'decisionAt': review['decided_at'],
          'contentHash': review['content_hash'],
          'backendFindings': findings,
          'brandName': review['brand_name']?.toString() ?? '',
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _backendReviews = mappedReviews;
        isLoading = false;
        loadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = e.toString();
      });
    }
  }

  Future<Map<String, dynamic>> _reviewsWithRetry() async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await BrandGuardApiService.getReviews();
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    throw lastError ?? Exception('Review queue did not load.');
  }

  List<Map<String, dynamic>> get filteredReviews {
    if (selectedTab == 'All') return reviews;

    return reviews.where((item) => item['status'] == selectedTab).toList();
  }

  int get pendingCount =>
      reviews.where((item) => item['status'] == 'Pending').length;

  int get approvedCount =>
      reviews.where((item) => item['status'] == 'Approved').length;

  int get rejectedCount =>
      reviews.where((item) => item['status'] == 'Rejected').length;

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Tone statusTone(String status) {
    switch (status) {
      case 'Approved':
        return Tone.success;
      case 'Changes Requested':
        return Tone.warning;
      case 'Rejected':
        return Tone.danger;
      default:
        return Tone.info;
    }
  }

  Tone riskTone(String risk) {
    switch (risk) {
      case 'High':
        return Tone.danger;
      case 'Medium':
        return Tone.warning;
      default:
        return Tone.success;
    }
  }

  Future<void> updateReview(
    Map<String, dynamic> review,
    String decision,
    BuildContext sheetContext,
  ) async {
    if (review['status'] == 'Approved' || review['status'] == 'Rejected') {
      showMessage('This review already has a final decision.');
      return;
    }

    final backendDecision = decision == 'Approved' ? 'approved' : 'rejected';

    try {
      await BrandGuardApiService.decideReview(
        checkId: review['id'].toString(),
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: decision == 'Approved'
            ? 'Approved by authorised reviewer.'
            : 'Rejected by authorised reviewer.',
      );

      if (!mounted || !sheetContext.mounted) return;

      Navigator.pop(sheetContext);

      await _loadReviews();

      showMessage('Review status updated: $decision');
    } catch (e) {
      showMessage('Unable to update review: $e');
    }
  }

  Future<void> openReviewDetails(Map<String, dynamic> review) async {
    final decision = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, updateSheet) {
            final status = review['status'] as String;
            final findings = (review['backendFindings'] as List)
                .whereType<Map>()
                .map((f) => Map<String, dynamic>.from(f))
                .toList();
            final canDecide =
                (status == 'Pending' || status == 'Changes Requested') &&
                (session.currentUser?.isReviewer ?? false) &&
                review['creatorId'] != session.userId;

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      height: 4,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Authorised review',
                                  style: AppTheme.titleMedium.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Review stage · the decision is bound to this exact version',
                                  style: AppTheme.monoLabel(),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        children: [
                          SurfaceCard(
                            color: AppTheme.navy,
                            borderColor: AppTheme.navy,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusPill(
                                      label: review['version'],
                                      tone: Tone.neutral,
                                      solid: true,
                                    ),
                                    const SizedBox(width: 6),
                                    StatusPill(
                                      label: status,
                                      tone: statusTone(status),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.shield_outlined,
                                      size: 18,
                                      color: AppTheme.mintBright,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  review['title'],
                                  style: AppTheme.titleMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Check ${review['id']}',
                                  style: AppTheme.monoLabel(
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.policy_outlined,
                                        size: 15,
                                        color: AppTheme.mintBright,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          'Creators cannot approve their own content. Reviewer sign-off binds the exact hashed version.',
                                          style: AppTheme.bodySmall.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _detailSection('CONTENT INFORMATION', [
                            _detailRow('Content ID', review['id']),
                            _detailRow('Content version', review['version']),
                            _detailRow('Rules version', review['rulesVersion']),
                            _detailRow('Creator', review['creator']),
                            _detailRow('Submitted', review['date']),
                            if (review['contentHash'] != null)
                              _detailRow(
                                'Content hash',
                                _shortHash(review['contentHash'].toString()),
                              ),
                          ]),
                          if (findings.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _detailSection('REQUIRED EVIDENCE CHECKLIST', [
                              for (final finding in findings)
                                _findingChecklistRow(finding),
                            ]),
                          ],
                          const SizedBox(height: 12),
                          _detailSection('INSPECTION SUMMARY', [
                            _detailRow(
                              'Total findings',
                              '${review['findings']}',
                            ),
                            _detailRow('Risk level', review['risk']),
                            _detailRow('Review status', review['status']),
                          ]),
                          if (review['decisionAt'] != null) ...[
                            const SizedBox(height: 12),
                            _detailSection('LATEST DECISION', [
                              _detailRow('Decision', review['status']),
                              _detailRow(
                                'Reviewer',
                                (review['decisionBy'] ?? 'Authorised Reviewer')
                                    .toString(),
                              ),
                              _detailRow(
                                'Recorded at',
                                _formatDecisionTime(
                                  review['decisionAt'].toString(),
                                ),
                              ),
                              _detailRow(
                                'Reason',
                                (review['decisionReason'] ?? '—').toString(),
                              ),
                            ]),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            'SUBMITTED CONTENT',
                            style: AppTheme.monoLabel(),
                          ),
                          const SizedBox(height: 6),
                          SurfaceCard(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              (review['contentText'] as String).isNotEmpty
                                  ? review['contentText'] as String
                                  : review['description'] as String,
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.ink,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const InlineNotice(
                            tone: Tone.info,
                            icon: Icons.lock_outline_rounded,
                            title: 'Approval is version-bound',
                            message: 'Approval applies to this exact content version only. Any later edit invalidates it and requires a new review.',
                          ),
                          if (findings.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'DETECTED FINDINGS',
                                    style: AppTheme.monoLabel(),
                                  ),
                                  const SizedBox(height: 8),
                                  ...findings.map(
                                    (finding) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.flag_rounded,
                                            size: 14,
                                            color: riskTone(
                                              (finding['severity']
                                                              ?.toString() ??
                                                          'review')
                                                      .toLowerCase()
                                                      .contains('critical')
                                                  ? 'High'
                                                  : 'Medium',
                                            ).fg,
                                          ),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  finding['rule_id']
                                                          ?.toString() ??
                                                      'RULE',
                                                  style: AppTheme.monoLabel(
                                                    color: AppTheme.ink,
                                                  ),
                                                ),
                                                Text(
                                                  finding['message']
                                                          ?.toString() ??
                                                      '',
                                                  style: AppTheme.bodySmall
                                                      .copyWith(
                                                        color: AppTheme.ink,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: AppTheme.border)),
                      ),
                      child: canDecide
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton.icon(
                                    key: const ValueKey('approve-review'),
                                    onPressed: () => updateReview(
                                      review,
                                      'Approved',
                                      sheetContext,
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.teal,
                                    ),
                                    icon: const Icon(
                                      Icons.lock_rounded,
                                      size: 17,
                                    ),
                                    label: const Text(
                                      'Authorise & cryptographically lock',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(
                                          sheetContext,
                                          'Changes Requested',
                                        ),
                                        child: const Text('Request changes'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        key: const ValueKey('reject-review'),
                                        onPressed: () => Navigator.pop(
                                          sheetContext,
                                          'Rejected',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.danger,
                                          backgroundColor: AppTheme.dangerBg,
                                          side: BorderSide(
                                            color: AppTheme.danger.withValues(
                                              alpha: 0.35,
                                            ),
                                          ),
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : InlineNotice(
                              tone: status == 'Pending'
                                  ? Tone.info
                                  : Tone.success,
                              title: status == 'Pending'
                                  ? 'Only a separate reviewer can decide'
                                  : 'Final decision already recorded',
                              message: status == 'Pending'
                                  ? 'You cannot approve your own submission. Ask another authorised reviewer.'
                                  : 'This submission is closed. Produce a new version to request another review.',
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || decision == null) return;

    if (decision == 'Rejected' || decision == 'Changes Requested') {
      await _showDecisionDialog(review, decision);
    }
  }

  String _shortHash(String value) {
    if (value.length <= 20) return value;
    return '${value.substring(0, 12)}…${value.substring(value.length - 6)}';
  }

  Widget _findingChecklistRow(Map<String, dynamic> finding) {
    final severity = finding['severity']?.toString().toLowerCase() ?? 'review';
    final tone = severity.contains('critical')
        ? Tone.danger
        : severity.contains('warning')
        ? Tone.warning
        : Tone.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tone.icon, size: 15, color: tone.fg),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finding['rule_id']?.toString() ?? 'RULE',
                  style: AppTheme.monoLabel(color: AppTheme.ink),
                ),
                Text(
                  (finding['message'] ?? finding['evidence'] ?? '').toString(),
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          StatusPill(label: severity, tone: tone, compact: true),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return SurfaceCard(
      padding: const EdgeInsets.all(13),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.monoLabel()),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: AppTheme.bodySmall)),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTheme.labelMedium.copyWith(
                fontSize: 11.5,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDecisionDialog(
    Map<String, dynamic> review,
    String decision,
  ) async {
    final controller = TextEditingController();

    try {
      final reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(decision),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    decision == 'Rejected'
                        ? 'Provide a reason for rejecting this content.'
                        : 'Describe the changes required before approval.',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Enter decision reason…',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final enteredReason = controller.text.trim();
                  if (enteredReason.isEmpty) return;
                  Navigator.pop(dialogContext, enteredReason);
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );

      if (!mounted || reason == null || reason.isEmpty) return;

      // The current backend supports approved and rejected decisions.
      const backendDecision = 'rejected';

      final backendReason = decision == 'Changes Requested'
          ? 'Changes requested: $reason'
          : reason;

      await BrandGuardApiService.decideReview(
        checkId: review['id'].toString(),
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: backendReason,
      );

      if (!mounted) return;

      await _loadReviews();

      if (!mounted) return;

      showMessage('$decision recorded successfully.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Unable to record decision: $e');
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
        children: [
          PageIntro(
            eyebrow: 'LEDGER LIVE',
            eyebrowTone: Tone.success,
            title: 'Authorised review queue',
            subtitle: 'No finding without evidence. Sign-off binds the exact version reviewed.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Pending',
                  value: '$pendingCount',
                  tone: pendingCount > 0 ? Tone.warning : Tone.success,
                  icon: Icons.pending_actions_rounded,
                  footnote: 'Awaiting decision',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricCard(
                  label: 'Approved',
                  value: '$approvedCount',
                  tone: Tone.success,
                  icon: Icons.verified_rounded,
                  footnote: 'Signed off',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricCard(
                  label: 'Rejected',
                  value: '$rejectedCount',
                  tone: Tone.danger,
                  icon: Icons.cancel_outlined,
                  footnote: 'Blocked',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionHeading(
            title: 'Review queue',
            caption: 'Scoped to the submissions you may inspect',
          ),
          const SizedBox(height: 10),
          _tabs(),
          const SizedBox(height: 12),
          if (isLoading)
            const LoadingBlock(label: 'Loading review records…')
          else if (loadError != null)
            ErrorBlock(
              title: 'Unable to load reviews',
              message: loadError!,
              onRetry: _loadReviews,
            )
          else if (filteredReviews.isEmpty)
            EmptyStateCard(
              title: 'Nothing in this category',
              message: 'Submitted checks appear here as soon as the backend records them.',
              icon: Icons.inbox_outlined,
            )
          else
            ...filteredReviews.map(_reviewCard),
          const SizedBox(height: 20),
          _ledgerSection(),
        ],
      ),
    );

    if (widget.embedded) {
      return Column(
        children: [
          const ShellHeader(
            title: 'Reviews',
            subtitle: 'Evidence-bound decisions',
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Review & approval'),
        actions: [
          IconButton(
            tooltip: 'Reload queue',
            onPressed: _loadReviews,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _tabs() {
    final tabs = ['Pending', 'Approved', 'Rejected', 'All'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final active = selectedTab == tab;
          final count = switch (tab) {
            'Pending' => pendingCount,
            'Approved' => approvedCount,
            'Rejected' => rejectedCount,
            _ => reviews.length,
          };
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: GestureDetector(
              onTap: () => setState(() => selectedTab = tab),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? AppTheme.mint : AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? AppTheme.teal : AppTheme.border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      tab,
                      style: AppTheme.labelMedium.copyWith(
                        fontSize: 11.5,
                        color: active ? AppTheme.tealText : AppTheme.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active ? AppTheme.teal : const Color(0xFFF2F5F4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: AppTheme.monoLabel(
                          color: active ? Colors.white : AppTheme.muted,
                        ).copyWith(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        radius: 18,
        onTap: () => openReviewDetails(review),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(
                  label: review['version'],
                  tone: Tone.neutral,
                  solid: true,
                  compact: true,
                ),
                const SizedBox(width: 6),
                StatusPill(
                  label: review['status'],
                  tone: statusTone(review['status']),
                  compact: true,
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              review['title'],
              style: AppTheme.labelLarge.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 13,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Created by ${review['creator']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoLabel(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(
                  label: '${review['findings']} findings',
                  tone: (review['findings'] as int) > 0
                      ? Tone.danger
                      : Tone.success,
                  compact: true,
                ),
                StatusPill(
                  label: '${review['risk']} risk',
                  tone: riskTone(review['risk']),
                  compact: true,
                ),
                StatusPill(label: review['date'], compact: true),
                StatusPill(
                  label: review['rulesVersion'],
                  tone: Tone.info,
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDecisionTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} • ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _ledgerSection() {
    final completedReviews = reviews.where(
      (item) =>
          item['status'] == 'Approved' ||
          item['status'] == 'Rejected' ||
          item['status'] == 'Changes Requested',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Approval ledger',
          caption: 'Immutable decisions returned by the API',
        ),
        const SizedBox(height: 10),
        if (completedReviews.isEmpty)
          const EmptyStateCard(
            title: 'No decisions recorded yet',
            message: 'Approved and rejected submissions appear here with their reviewer and timestamp.',
            icon: Icons.receipt_long_outlined,
          )
        else
          ...completedReviews.map(
            (review) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.all(12),
                radius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          statusTone(review['status']).icon,
                          size: 16,
                          color: statusTone(review['status']).fg,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            review['title'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.labelMedium.copyWith(
                              fontSize: 12,
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                        StatusPill(
                          label: review['status'],
                          tone: statusTone(review['status']),
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${review['version']} · ${review['id'].toString().length > 8 ? review['id'].toString().substring(0, 8) : review['id']}',
                      style: AppTheme.monoLabel(),
                    ),
                    if (review['decisionBy'] != null)
                      Text(
                        'Reviewer: ${review['decisionBy']}',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                      ),
                    if (review['decisionAt'] != null)
                      Text(
                        'Recorded: ${_formatDecisionTime(review['decisionAt'].toString())}',
                        style: AppTheme.bodySmall,
                      ),
                    if (review['decisionReason'] != null)
                      Text(
                        'Reason: ${review['decisionReason']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
