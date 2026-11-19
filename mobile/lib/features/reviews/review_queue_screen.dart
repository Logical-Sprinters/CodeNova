import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../checks/new_brand_check_screen.dart';
import '../governance/conflicts_screen.dart';

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({
    super.key,
    this.embedded = false,
    this.refreshTick = 0,
    this.initialTab = 'Pending',
    this.initialCheckId,
  });

  final bool embedded;
  final int refreshTick;
  final String initialTab;
  final String? initialCheckId;

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  static const List<(String, String)> _overrideReasons = [
    ('FALSE_POSITIVE', 'False positive'),
    ('APPROVED_EXCEPTION', 'Approved exception'),
    ('AMBIGUOUS_RULE_TEXT', 'Ambiguous rule text'),
    ('OUTDATED_RULE_OR_FACT', 'Outdated rule/fact'),
    ('CONTEXTUAL_QUALIFIER', 'Contextual qualifier'),
    ('CHANNEL_EXEMPTION', 'Channel exemption'),
  ];

  late String selectedTab = widget.initialTab;
  bool _openedInitialCheck = false;
  bool _fetching = false;
  bool _queuedReload = false;

  List<Map<String, dynamic>> _backendReviews = [];
  bool isLoading = true;
  String? loadError;

  List<Map<String, dynamic>> get reviews => _backendReviews;

  @override
  void initState() {
    super.initState();
    BrandGuardApiService.syncTick.addListener(_onDataSynced);
    _loadReviews();
  }

  @override
  void didUpdateWidget(covariant ReviewQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _loadReviews(silent: true);
    }
  }

  @override
  void dispose() {
    BrandGuardApiService.syncTick.removeListener(_onDataSynced);
    super.dispose();
  }

  void _onDataSynced() {
    if (mounted) _loadReviews(silent: true);
  }

  Future<void> _loadReviews({bool silent = false}) async {
    if (_fetching) {
      _queuedReload = true;
      return;
    }
    _fetching = true;
    _queuedReload = false;
    if (!silent && !isLoading) setState(() => isLoading = true);
    try {
      final result = await _reviewsWithRetry();

      final List<dynamic> records = result['reviews'] ?? [];

      final mappedReviews = records.map((item) {
        final review = Map<String, dynamic>.from(item);

        final findings = (review['findings'] as List?) ?? [];
        final assetIds = (review['asset_ids'] as List?) ?? [];
        final conflicts = (review['conflicts'] as List?) ?? [];

        final createdAtRaw = review['created_at']?.toString();
        final updatedAtRaw = review['updated_at']?.toString();
        final createdAt = DateTime.tryParse(createdAtRaw ?? '')?.toLocal();
        final updatedAt = DateTime.tryParse(updatedAtRaw ?? '')?.toLocal();
        final sortInstant =
            updatedAt ??
            createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

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
        final rawNote = review['review_note']?.toString() ?? '';
        final mappedStatus = switch (rawStatus) {
          'approved' => 'Approved',
          'changes_requested' => 'Changes Requested',
          'rejected' when rawNote.startsWith('Changes requested:') =>
            'Changes Requested',
          'rejected' => 'Rejected',
          'paused_conflict' || 'review_paused_conflict' => 'Conflict',
          'completed' => 'Completed',
          _ => 'Pending',
        };
        final contentVer = (review['content_version'] as num?)?.toInt() ?? 1;
        final versionLabel =
            contentVer <= 1 ? 'Submission' : 'Rev $contentVer';
        final creatorId = review['creator_id']?.toString() ?? 'Unknown';
        final creatorName =
            (review['creator_name']?.toString().trim().isNotEmpty ?? false)
            ? review['creator_name'].toString().trim()
            : creatorId;
        final creatorEmail =
            review['creator_email']?.toString().trim() ?? '';
        final reviewerId = review['reviewer']?.toString();
        final reviewerName =
            (review['reviewer_name']?.toString().trim().isNotEmpty ?? false)
            ? review['reviewer_name'].toString().trim()
            : reviewerId;
        final reviewerEmail =
            review['reviewer_email']?.toString().trim() ?? '';
        final aiVerification = review['ai_verification'] is Map
            ? Map<String, dynamic>.from(review['ai_verification'] as Map)
            : null;
        final aiStatus = aiVerification?['status']?.toString();
        final decisionHistory = (review['decision_history'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        return <String, dynamic>{
          'id': review['check_id']?.toString() ?? '',
          'parentCheckId': review['parent_check_id']?.toString(),
          'title': '${review['brand_name'] ?? 'Unknown'} Brand Check',
          'creator': creatorName,
          'creatorName': creatorName,
          'creatorEmail': creatorEmail,
          'channel': review['channel']?.toString() ?? 'all',
          'checkAt': review['check_at']?.toString(),
          'assetIds': assetIds.map((e) => e.toString()).toList(),
          'conflicts': conflicts,
          'date': _formatExactLocalDateTime(createdAtRaw),
          'createdAtRaw': createdAtRaw,
          'updatedAtRaw': updatedAtRaw,
          'sortEpochMs': sortInstant.millisecondsSinceEpoch,
          'status': mappedStatus,
          'findings': findings.length,
          'version': versionLabel,
          'contentVersion': contentVer,
          'creatorId': creatorId,
          'contentText': review['content']?.toString() ?? '',
          'ocrText': review['ocr_text']?.toString() ?? '',
          'rulesVersion': review['rules_version']?.toString() ?? 'Base rules',
          'aiStatus': aiStatus,
          'risk': risk,
          'description':
              'Automated brand compliance check for ${review['brand_name']}. '
              'This review contains ${findings.length} detected findings.',
          'decisionBy': reviewerName,
          'decisionByEmail': reviewerEmail,
          'decisionReason': review['review_note'],
          'decisionAt': review['decided_at'],
          'canAmend': review['can_amend'] == true,
          'amendWindowMinutes':
              (review['amend_window_minutes'] as num?)?.toInt() ?? 60,
          'amendDeadline': review['amend_deadline']?.toString(),
          'amendRemainingSeconds':
              (review['amend_remaining_seconds'] as num?)?.toInt() ?? 0,
          'decisionHistory': decisionHistory,
          'contentHash': review['content_hash'],
          'compositeHash': review['composite_hash'],
          'backendFindings': findings,
          'brandName': review['brand_name']?.toString() ?? '',
        };
      }).toList()
        ..sort(
          (a, b) => (b['sortEpochMs'] as int).compareTo(a['sortEpochMs'] as int),
        );

      if (!mounted) return;

      setState(() {
        _backendReviews = mappedReviews;
        isLoading = false;
        loadError = null;
      });

      final targetId = widget.initialCheckId;
      if (targetId != null && !_openedInitialCheck) {
        _openedInitialCheck = true;
        final match = mappedReviews
            .where((r) => r['id'] == targetId)
            .toList();
        if (match.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) openReviewDetails(match.first);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent || _backendReviews.isEmpty) {
        setState(() {
          isLoading = false;
          loadError = e.toString();
        });
      }
    } finally {
      _fetching = false;
      if (_queuedReload && mounted) {
        _queuedReload = false;
        _loadReviews(silent: true);
      }
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

  int get changesRequestedCount =>
      reviews.where((item) => item['status'] == 'Changes Requested').length;

  int get conflictCount =>
      reviews.where((item) => item['status'] == 'Conflict').length;

  int get approvedCount =>
      reviews.where((item) => item['status'] == 'Approved').length;

  int get rejectedCount =>
      reviews.where((item) => item['status'] == 'Rejected').length;

  void showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.navy,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
  }

  Tone statusTone(String status) {
    switch (status) {
      case 'Approved':
        return Tone.success;
      case 'Conflict':
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

  Future<void> _overrideFindingFromQueue(
    String checkId,
    Map<String, dynamic> finding,
  ) async {
    final findingId = finding['finding_id']?.toString() ?? '';
    if (findingId.isEmpty) return;

    var selectedReason = _overrideReasons.first.$1;
    final noteCtrl = TextEditingController();
    var busy = false;
    String? dlgError;

    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Log coded override'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select why ${finding['rule_id']} is being overridden:',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 8),
                  for (final item in _overrideReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SurfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        radius: 10,
                        borderColor: selectedReason == item.$1
                            ? AppTheme.teal
                            : AppTheme.border,
                        color: selectedReason == item.$1
                            ? AppTheme.mint
                            : AppTheme.card,
                        onTap: () => setDlg(() => selectedReason = item.$1),
                        child: Row(
                          children: [
                            Icon(
                              selectedReason == item.$1
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 15,
                              color: selectedReason == item.$1
                                  ? AppTheme.teal
                                  : AppTheme.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.$2,
                                style: AppTheme.labelMedium.copyWith(
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reviewer note',
                    ),
                  ),
                  if (dlgError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      dlgError!,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDlg(() {
                        busy = true;
                        dlgError = null;
                      });
                      try {
                        final res = await BrandGuardApiService.overrideFinding(
                          checkId: checkId,
                          findingId: findingId,
                          reasonCode: selectedReason,
                          note: noteCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, res);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() {
                            busy = false;
                            dlgError = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving...' : 'Confirm override'),
            ),
          ],
        ),
      ),
    );
    try {
      final result = await Navigator.of(context).push(route);
      if (result != null && mounted) {
        await _loadReviews();
        final opened = result['clarity_ticket'] != null;
        showMessage(
          opened
              ? 'Override logged — Clarity Ticket opened.'
              : 'Override logged ($selectedReason).',
        );
      }
    } finally {
      await route.completed;
      noteCtrl.dispose();
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
      final checkId = review['id'].toString();
      await BrandGuardApiService.decideReview(
        checkId: checkId,
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: decision == 'Approved'
            ? 'Approved by authorised reviewer.'
            : 'Rejected by authorised reviewer.',
      );

      if (!mounted || !sheetContext.mounted) return;

      Navigator.pop(sheetContext);

      await _loadReviews();

      if (!mounted) return;
      final refreshed = reviews.where((r) => r['id'] == checkId).toList();
      showMessage(
        'Review status updated: $decision',
        action: refreshed.isNotEmpty && _withinAmendWindow(refreshed.first)
            ? SnackBarAction(
                label: 'Undo / Amend',
                textColor: AppTheme.mintBright,
                onPressed: () {
                  if (mounted) _showAmendDecisionDialog(refreshed.first);
                },
              )
            : null,
      );
    } catch (e) {
      showMessage('Unable to update review: $e');
    }
  }

  Future<void> openReviewDetails(Map<String, dynamic> review) async {
    Map<String, dynamic>? overrideTarget;
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
            final assetIds = (review['assetIds'] as List? ?? [])
                .map((e) => e.toString())
                .toList();
            final isReviewer = session.currentUser?.isReviewer ?? false;
            final isOwner = review['creatorId'] == session.userId;
            final canDecide =
                status == 'Pending' && isReviewer && !isOwner;
            final canEditResubmit =
                isOwner &&
                (status == 'Changes Requested' ||
                    status == 'Rejected' ||
                    status == 'Pending');
            final canAmendStatus =
                isReviewer &&
                !isOwner &&
                (status == 'Approved' ||
                    status == 'Rejected' ||
                    status == 'Changes Requested');
            final withinAmendWindow =
                canAmendStatus && _withinAmendWindow(review);
            final windowMinutes =
                (review['amendWindowMinutes'] as int?) ?? 60;
            final decisionHistory =
                (review['decisionHistory'] as List? ?? [])
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
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
                                  'Review stage · composite seal binds caption & assets',
                                  style: AppTheme.monoLabel(),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('close-review-sheet'),
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
                                    Flexible(
                                      child: StatusPill(
                                        label: review['version'],
                                        tone: Tone.neutral,
                                        solid: true,
                                        compact: true,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: StatusPill(
                                        label: status,
                                        tone: statusTone(status),
                                        compact: true,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
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
                                      Icon(
                                        Icons.policy_outlined,
                                        size: 15,
                                        color: AppTheme.mintBright,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          'Creators cannot approve their own content. Reviewer sign-off cryptographically seals this exact text & asset bundle.',
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
                          if (status == 'Changes Requested') ...[
                            const SizedBox(height: 12),
                            InlineNotice(
                              tone: Tone.warning,
                              icon: Icons.edit_note_rounded,
                              title: 'Changes requested by reviewer',
                              message:
                                  (review['decisionReason']?.toString() ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? review['decisionReason'].toString()
                                  : 'Update your submission copy or assets and resubmit for review.',
                            ),
                          ],
                          if (status == 'Conflict') ...[
                            const SizedBox(height: 12),
                            InlineNotice(
                              tone: Tone.warning,
                              title: 'Paused due to internal rule conflict',
                              message:
                                  'Resolve the contradictory rule or fact source before this submission can be approved.',
                              action: FilledButton.icon(
                                onPressed: () => Navigator.pop(
                                  sheetContext,
                                  'OPEN_CONFLICTS',
                                ),
                                icon: const Icon(Icons.balance_rounded, size: 16),
                                label: const Text('Resolve conflict'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _detailSection('AUTHORED BY & TIMELINE', [
                            _detailRow(
                              'Created by',
                              review['creatorName'].toString(),
                            ),
                            if ((review['creatorEmail']?.toString() ?? '')
                                .isNotEmpty)
                              _detailRow(
                                'Author email',
                                review['creatorEmail'].toString(),
                              ),
                            _detailRow(
                              'Submitted at',
                              review['date'].toString(),
                            ),
                            if (review['updatedAtRaw'] != null &&
                                review['updatedAtRaw'] !=
                                    review['createdAtRaw'])
                              _detailRow(
                                'Last updated',
                                _formatExactLocalDateTime(
                                  review['updatedAtRaw']?.toString(),
                                ),
                              ),
                            _detailRow(
                              'Target channel',
                              review['channel'].toString() == 'all'
                                  ? 'All channels'
                                  : review['channel'].toString(),
                            ),
                            if (review['checkAt'] != null)
                              _detailRow(
                                'Rules evaluated as of',
                                _formatRuleWindowDate(
                                  review['checkAt']?.toString(),
                                  review['createdAtRaw']?.toString(),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 12),
                          _detailSection('SUBMISSION & EVIDENCE DETAILS', [
                            _detailRow('Check ID', review['id'].toString()),
                            if ((review['parentCheckId']?.toString() ?? '')
                                .isNotEmpty)
                              _detailRow(
                                'Derived from check',
                                _shortHash(review['parentCheckId'].toString()),
                              ),
                            _detailRow(
                              'Submission stage',
                              (review['contentVersion'] as int? ?? 1) <= 1
                                  ? 'Initial submission'
                                  : 'Revision ${review['contentVersion']}',
                            ),
                            _detailRow(
                              'Active ruleset',
                              review['rulesVersion'].toString(),
                            ),
                            _detailRow(
                              'Attached assets',
                              assetIds.isEmpty
                                  ? 'None (text only)'
                                  : '${assetIds.length} attachment${assetIds.length == 1 ? '' : 's'}',
                            ),
                            _detailRow(
                              'Findings & risk',
                              '${review['findings']} · ${review['risk']} risk',
                            ),
                            if ((review['aiStatus']?.toString() ?? '')
                                .isNotEmpty)
                              _detailRow(
                                'AI comparison',
                                review['aiStatus']
                                    .toString()
                                    .replaceAll('_', ' '),
                              ),
                            if (review['contentHash'] != null)
                              _detailRow(
                                'Content SHA-256',
                                _shortHash(review['contentHash'].toString()),
                              ),
                            if (review['compositeHash'] != null)
                              _detailRow(
                                'Composite SHA-256',
                                _shortHash(review['compositeHash'].toString()),
                              ),
                          ]),
                          if (findings.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _detailSection('REQUIRED EVIDENCE CHECKLIST', [
                              for (final finding in findings)
                                _findingChecklistRow(
                                  finding,
                                  checkId: review['id'].toString(),
                                  isReviewer: isReviewer,
                                  onOverrideTap: () {
                                    overrideTarget = finding;
                                    Navigator.pop(
                                      sheetContext,
                                      'OVERRIDE_FINDING',
                                    );
                                  },
                                ),
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
                              if ((review['decisionByEmail']
                                          ?.toString() ??
                                      '')
                                  .isNotEmpty)
                                _detailRow(
                                  'Reviewer email',
                                  review['decisionByEmail'].toString(),
                                ),
                              _detailRow(
                                'Recorded at',
                                _formatDecisionTime(
                                  review['decisionAt'].toString(),
                                ),
                              ),
                              _detailRow(
                                'Feedback / reason',
                                (review['decisionReason'] ?? '—').toString(),
                              ),
                              if (canAmendStatus)
                                _detailRow(
                                  'Grace window',
                                  withinAmendWindow
                                      ? '${_formatAmendRemaining(review)} ($windowMinutes min limit)'
                                      : 'Closed ($windowMinutes min limit expired)',
                                ),
                              if (withinAmendWindow) ...[
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.pop(
                                      sheetContext,
                                      'AMEND_DECISION',
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: status == 'Approved'
                                          ? AppTheme.danger
                                          : AppTheme.tealText,
                                      side: BorderSide(
                                        color: status == 'Approved'
                                            ? AppTheme.danger.withValues(
                                                alpha: 0.4,
                                              )
                                            : AppTheme.teal,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.undo_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      status == 'Approved'
                                          ? 'Revoke / switch decision'
                                          : 'Amend / switch decision',
                                    ),
                                  ),
                                ),
                              ],
                            ]),
                          ],
                          if (decisionHistory.length > 1) ...[
                            const SizedBox(height: 12),
                            _detailSection('DECISION HISTORY', [
                              for (final entry in decisionHistory.reversed)
                                _detailRow(
                                  '${_formatDecisionLabel(entry['decision']?.toString() ?? '')} (${entry['kind'] == 'amended' ? 'Amended' : 'Initial'})',
                                  '${entry['reviewer_name'] ?? entry['reviewer'] ?? 'Reviewer'} · ${_formatDecisionTime((entry['decided_at'] ?? '').toString())}\n${(entry['note'] ?? '').toString()}',
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
                          if ((review['ocrText'] as String).isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'IMAGE OCR TEXT',
                              style: AppTheme.monoLabel(),
                            ),
                            const SizedBox(height: 6),
                            SurfaceCard(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                review['ocrText'] as String,
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const InlineNotice(
                            tone: Tone.info,
                            icon: Icons.lock_outline_rounded,
                            title: 'Approval is version-bound & sealed',
                            message:
                                'Approval seals this exact text, asset hashes, and rule version. Any later edit invalidates the seal.',
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
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
                          : canEditResubmit
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton.icon(
                                    key: const ValueKey(
                                      'edit-resubmit-review',
                                    ),
                                    onPressed: () => Navigator.pop(
                                      sheetContext,
                                      'EDIT_RESUBMIT',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.teal,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      status == 'Changes Requested'
                                          ? 'Edit & resubmit changes'
                                          : 'Edit & resubmit',
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : status == 'Approved' && isOwner
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InlineNotice(
                                  tone: Tone.success,
                                  title: 'Final decision already recorded',
                                  message:
                                      'This submission is cryptographically sealed. Create a new revised check to edit copy without modifying the approved record.',
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    key: const ValueKey(
                                      'revise-approved-review',
                                    ),
                                    onPressed: () => Navigator.pop(
                                      sheetContext,
                                      'REVISE_APPROVED',
                                    ),
                                    icon: const Icon(
                                      Icons.content_copy_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Edit as new check'),
                                  ),
                                ),
                              ],
                            )
                          : canAmendStatus
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (withinAmendWindow) ...[
                                  InlineNotice(
                                    tone: status == 'Approved'
                                        ? Tone.warning
                                        : Tone.info,
                                    title: status == 'Approved'
                                        ? 'Approval recorded (${_formatAmendRemaining(review)})'
                                        : 'Decision recorded (${_formatAmendRemaining(review)})',
                                    message: status == 'Approved'
                                        ? 'Accidental decision? You have ${_formatAmendRemaining(review)} ($windowMinutes min window) to revoke or amend. Revoking invalidates the cryptographic seal.'
                                        : 'Accidental decision? You have ${_formatAmendRemaining(review)} ($windowMinutes min window) to amend this decision.',
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 46,
                                    child: OutlinedButton.icon(
                                      key: const ValueKey(
                                        'amend-decision-button',
                                      ),
                                      onPressed: () => Navigator.pop(
                                        sheetContext,
                                        'AMEND_DECISION',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: status == 'Approved'
                                            ? AppTheme.danger
                                            : AppTheme.tealText,
                                        side: BorderSide(
                                          color: status == 'Approved'
                                              ? AppTheme.danger.withValues(
                                                  alpha: 0.4,
                                                )
                                              : AppTheme.teal,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.undo_rounded,
                                        size: 17,
                                      ),
                                      label: Text(
                                        status == 'Approved'
                                            ? 'Revoke / amend decision'
                                            : 'Amend decision',
                                      ),
                                    ),
                                  ),
                                ] else
                                  InlineNotice(
                                    tone: status == 'Approved'
                                        ? Tone.success
                                        : Tone.info,
                                    title: 'Amendment window closed',
                                    message:
                                        'The $windowMinutes-minute reversal window has expired. Ask the owner to submit a new revision if changes are still needed.',
                                  ),
                              ],
                            )
                          : InlineNotice(
                              tone: status == 'Conflict'
                                  ? Tone.warning
                                  : status == 'Changes Requested'
                                  ? Tone.warning
                                  : status == 'Pending'
                                  ? Tone.info
                                  : Tone.success,
                              title: status == 'Conflict'
                                  ? 'Blocked on open policy conflict'
                                  : status == 'Changes Requested'
                                  ? 'Waiting on creator revision'
                                  : status == 'Pending'
                                  ? 'Only a separate reviewer can decide'
                                  : 'Final decision already recorded',
                              message: status == 'Conflict'
                                  ? 'Resolve the conflicting rule or fact first.'
                                  : status == 'Changes Requested'
                                  ? 'Changes were requested. The creator can edit and resubmit this check for a new review.'
                                  : status == 'Pending'
                                  ? 'You cannot approve your own submission. Ask another authorised reviewer.'
                                  : 'This submission is closed.',
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

    if (decision == 'EDIT_RESUBMIT') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewBrandCheckScreen(
            resubmitCheckId: review['id'].toString(),
            expectedVersion: review['contentVersion'] as int?,
            initialBrandName: review['brandName']?.toString(),
            initialContent: review['contentText']?.toString(),
            initialChannel: review['channel']?.toString(),
            reviewerNote: review['decisionReason']?.toString(),
            reviewStatus: review['status']?.toString(),
          ),
        ),
      );
      if (mounted) await _loadReviews(silent: true);
      return;
    }

    if (decision == 'REVISE_APPROVED') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewBrandCheckScreen(
            parentApprovedCheckId: review['id'].toString(),
            initialAssetIds: (review['assetIds'] as List? ?? [])
                .map((e) => e.toString())
                .toList(),
            initialBrandName: review['brandName']?.toString(),
            initialContent: review['contentText']?.toString(),
            initialChannel: review['channel']?.toString(),
          ),
        ),
      );
      if (mounted) await _loadReviews(silent: true);
      return;
    }

    if (decision == 'OPEN_CONFLICTS') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ConflictsScreen()),
      );
      if (mounted) await _loadReviews();
      return;
    }

    if (decision == 'OVERRIDE_FINDING' && overrideTarget != null) {
      await _overrideFindingFromQueue(
        review['id'].toString(),
        overrideTarget!,
      );
      return;
    }

    if (decision == 'AMEND_DECISION') {
      await _showAmendDecisionDialog(review);
      return;
    }

    if (decision == 'Rejected' || decision == 'Changes Requested') {
      await _showDecisionDialog(review, decision);
    }
  }

  String _shortHash(String value) {
    if (value.length <= 20) return value;
    return '${value.substring(0, 12)}…${value.substring(value.length - 6)}';
  }

  Widget _findingChecklistRow(
    Map<String, dynamic> finding, {
    required String checkId,
    required bool isReviewer,
    required VoidCallback onOverrideTap,
  }) {
    final severity = finding['severity']?.toString().toLowerCase() ?? 'review';
    final tone = severity.contains('critical')
        ? Tone.danger
        : severity.contains('warning')
        ? Tone.warning
        : Tone.info;
    final overridden = finding['overridden'] == true;
    final findingId = finding['finding_id']?.toString() ?? '';
    final quote = finding['rule_quote']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tone.icon, size: 15, color: tone.fg),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${finding['rule_id'] ?? 'RULE'} · v${finding['rule_version'] ?? '1.0.0'}',
                      style: AppTheme.monoLabel(color: AppTheme.ink),
                    ),
                    Text(
                      (finding['message'] ?? finding['evidence'] ?? '')
                          .toString(),
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                    ),
                    if (quote.isNotEmpty)
                      Text(
                        '“$quote”',
                        style: AppTheme.bodySmall.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              StatusPill(
                label: overridden ? 'Overridden' : severity,
                tone: overridden ? Tone.warning : tone,
                compact: true,
              ),
            ],
          ),
          if (isReviewer && !overridden && findingId.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOverrideTap,
                icon: const Icon(Icons.rule_folder_outlined, size: 14),
                label: const Text('Override finding'),
              ),
            ),
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

  bool _withinAmendWindow(Map<String, dynamic> review) {
    final deadlineRaw = review['amendDeadline']?.toString();
    if (deadlineRaw != null && deadlineRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(deadlineRaw);
      if (parsed != null) {
        return !DateTime.now().toUtc().isAfter(parsed.toUtc());
      }
    }
    return review['canAmend'] == true;
  }

  String _formatAmendRemaining(Map<String, dynamic> review) {
    int seconds = (review['amendRemainingSeconds'] as int?) ?? 0;
    final deadlineRaw = review['amendDeadline']?.toString();
    if (deadlineRaw != null && deadlineRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(deadlineRaw);
      if (parsed != null) {
        final diff = parsed.toUtc().difference(DateTime.now().toUtc());
        seconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
      }
    }
    if (seconds <= 0) return 'Window expired';
    if (seconds < 60) return '<1m left';
    final mins = (seconds / 60).ceil();
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final rem = mins % 60;
      return rem == 0 ? '${hrs}h left' : '${hrs}h ${rem}m left';
    }
    return '${mins}m left';
  }

  String _formatDecisionLabel(String raw) {
    return switch (raw) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'changes_requested' => 'Changes Requested',
      _ => raw,
    };
  }

  Future<void> _showAmendDecisionDialog(Map<String, dynamic> review) async {
    final currentStatus = review['status']?.toString() ?? '';
    final choices = <(String, String)>[
      if (currentStatus != 'Approved') ('approved', 'Approve & lock seal'),
      if (currentStatus != 'Changes Requested')
        ('changes_requested', 'Request changes'),
      if (currentStatus != 'Rejected') ('rejected', 'Reject'),
    ];
    if (choices.isEmpty) return;
    var selectedDecision = currentStatus == 'Approved'
        ? 'rejected'
        : 'approved';
    if (!choices.any((c) => c.$1 == selectedDecision)) {
      selectedDecision = choices.first.$1;
    }
    final controller = TextEditingController();
    String? dlgError;
    var busy = false;
    final remainingText = _formatAmendRemaining(review);

    final route = DialogRoute<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            currentStatus == 'Approved'
                ? 'Revoke / amend approval'
                : 'Amend review decision',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentStatus == 'Approved') ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warningBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: AppTheme.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cryptographic seal will be revoked ($remainingText). Changing an approved decision immediately marks the seal REVOKED in Verification and notifies the owner.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Text(
                    'Current status: $currentStatus · $remainingText to amend.',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 10),
                ],
                Text('NEW DECISION', style: AppTheme.monoLabel()),
                const SizedBox(height: 6),
                for (final choice in choices)
                  InkWell(
                    onTap: busy
                        ? null
                        : () => setDlg(() {
                            selectedDecision = choice.$1;
                            dlgError = null;
                          }),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 5,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedDecision == choice.$1
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: selectedDecision == choice.$1
                                ? AppTheme.teal
                                : AppTheme.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              choice.$2,
                              style: AppTheme.labelMedium.copyWith(
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Amendment reason (required)',
                    hintText: 'Explain why this decision is being reversed…',
                  ),
                ),
                if (dlgError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dlgError!,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.danger),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-amend-decision'),
              onPressed: busy
                  ? null
                  : () async {
                      final reason = controller.text.trim();
                      if (reason.length < 3) {
                        setDlg(
                          () => dlgError =
                              'Enter an explanation of at least 3 characters.',
                        );
                        return;
                      }
                      setDlg(() {
                        busy = true;
                        dlgError = null;
                      });
                      try {
                        await BrandGuardApiService.amendReviewDecision(
                          checkId: review['id'].toString(),
                          decision: selectedDecision,
                          reason: reason,
                          expectedVersion: review['contentVersion'] as int?,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx, selectedDecision);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() {
                            busy = false;
                            dlgError = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Amending...' : 'Confirm amendment'),
            ),
          ],
        ),
      ),
    );

    try {
      final amended = await Navigator.of(context).push(route);
      if (!mounted || amended == null) return;
      await _loadReviews();
      showMessage(
        'Decision amended to ${_formatDecisionLabel(amended)}.',
      );
    } finally {
      await route.completed;
      controller.dispose();
    }
  }

  Future<void> _showDecisionDialog(
    Map<String, dynamic> review,
    String decision,
  ) async {
    final controller = TextEditingController();
    final route = DialogRoute<String>(
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

    try {
      final reason = await Navigator.of(context).push(route);

      if (!mounted || reason == null || reason.isEmpty) return;

      final backendDecision = decision == 'Changes Requested'
          ? 'changes_requested'
          : 'rejected';

      final checkId = review['id'].toString();
      await BrandGuardApiService.decideReview(
        checkId: checkId,
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: reason,
      );

      if (!mounted) return;

      await _loadReviews();

      if (!mounted) return;

      final refreshed = reviews.where((r) => r['id'] == checkId).toList();
      showMessage(
        '$decision recorded successfully.',
        action: refreshed.isNotEmpty && _withinAmendWindow(refreshed.first)
            ? SnackBarAction(
                label: 'Undo / Amend',
                textColor: AppTheme.mintBright,
                onPressed: () {
                  if (mounted) _showAmendDecisionDialog(refreshed.first);
                },
              )
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      showMessage('Unable to record decision: $e');
    } finally {
      await route.completed;
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
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
            subtitle:
                'No finding without evidence. Sign-off binds the exact text & asset bundle.',
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
              message:
                  'Submitted checks appear here as soon as the backend records them.',
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
    final tabs = [
      'Pending',
      'Changes Requested',
      'Conflict',
      'Approved',
      'Rejected',
      'All',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final active = selectedTab == tab;
          final count = switch (tab) {
            'Pending' => pendingCount,
            'Changes Requested' => changesRequestedCount,
            'Conflict' => conflictCount,
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
                        color: active ? AppTheme.teal : AppTheme.neutralBg,
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
    final assetCount = (review['assetIds'] as List? ?? []).length;
    final status = review['status']?.toString() ?? 'Pending';
    final isReviewer = session.currentUser?.isReviewer ?? false;
    final isOwner = review['creatorId'] == session.userId;
    final canAmendStatus =
        isReviewer &&
        !isOwner &&
        (status == 'Approved' ||
            status == 'Rejected' ||
            status == 'Changes Requested');
    final withinAmendWindow = canAmendStatus && _withinAmendWindow(review);
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
                Flexible(
                  child: StatusPill(
                    label: review['version'],
                    tone: Tone.neutral,
                    solid: true,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: StatusPill(
                    label: status,
                    tone: statusTone(status),
                    compact: true,
                  ),
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
                Icon(
                  Icons.person_outline_rounded,
                  size: 13,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    (review['creatorEmail']?.toString().isNotEmpty ?? false)
                        ? 'Drafted by ${review['creatorName']} · ${review['creatorEmail']}'
                        : 'Drafted by ${review['creatorName']}',
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
                StatusPill(
                  label: review['channel'].toString(),
                  tone: Tone.navy,
                  compact: true,
                ),
                if (assetCount > 0)
                  StatusPill(
                    label: '$assetCount asset${assetCount == 1 ? '' : 's'}',
                    tone: Tone.info,
                    compact: true,
                  ),
                StatusPill(label: review['date'], compact: true),
                StatusPill(
                  label: review['rulesVersion'],
                  tone: Tone.info,
                  compact: true,
                ),
                if (canAmendStatus)
                  StatusPill(
                    label: withinAmendWindow
                        ? 'Amendable · ${_formatAmendRemaining(review)}'
                        : 'Amend window closed',
                    tone: withinAmendWindow ? Tone.warning : Tone.neutral,
                    compact: true,
                  ),
              ],
            ),
            if (withinAmendWindow) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ValueKey('card-amend-${review['id']}'),
                  onPressed: () => _showAmendDecisionDialog(review),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: status == 'Approved'
                        ? AppTheme.danger
                        : AppTheme.tealText,
                    side: BorderSide(
                      color: status == 'Approved'
                          ? AppTheme.danger.withValues(alpha: 0.4)
                          : AppTheme.teal,
                    ),
                  ),
                  icon: const Icon(Icons.undo_rounded, size: 15),
                  label: Text(
                    status == 'Approved'
                        ? 'Revoke / switch decision'
                        : 'Amend / switch decision',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatRuleWindowDate(String? checkAt, String? createdAt) {
    if (checkAt == null || checkAt.trim().isEmpty) {
      return 'Current rules (at submission)';
    }
    final checkDt = DateTime.tryParse(checkAt.trim());
    final createdDt = createdAt == null
        ? null
        : DateTime.tryParse(createdAt.trim());
    if (checkDt != null &&
        createdDt != null &&
        checkDt.difference(createdDt).inSeconds.abs() <= 60) {
      return 'Current rules (at submission)';
    }
    return '${_formatExactLocalDateTime(checkAt)} (custom rule date)';
  }

  static String _formatExactLocalDateTime(String? value) {
    if (value == null || value.trim().isEmpty) return 'Unknown';
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return value;
    final local = parsed.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    String two(int v) => v.toString().padLeft(2, '0');
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absMins = offset.inMinutes.abs();
    final rawTz = local.timeZoneName.trim();
    final tzLabel = rawTz.isNotEmpty && rawTz.length <= 5
        ? rawTz
        : 'UTC$sign${two(absMins ~/ 60)}:${two(absMins % 60)}';
    return '${two(local.day)} ${months[local.month - 1]} ${local.year} · $hour12:${two(local.minute)} $amPm $tzLabel';
  }

  String _formatDecisionTime(String value) =>
      _formatExactLocalDateTime(value);

  Widget _ledgerSection() {
    final completedReviews = reviews.where(
      (item) =>
          item['status'] == 'Approved' ||
          item['status'] == 'Rejected' ||
          item['status'] == 'Changes Requested',
    );
    final isReviewer = session.currentUser?.isReviewer ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Approval ledger',
          caption: 'Tap any entry to inspect or amend within the grace window',
        ),
        const SizedBox(height: 10),
        if (completedReviews.isEmpty)
          const EmptyStateCard(
            title: 'No decisions recorded yet',
            message:
                'Approved and rejected submissions appear here with their reviewer and timestamp.',
            icon: Icons.receipt_long_outlined,
          )
        else
          ...completedReviews.map((review) {
            final status = review['status']?.toString() ?? '';
            final isOwner = review['creatorId'] == session.userId;
            final canAmend = isReviewer && !isOwner && _withinAmendWindow(review);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.all(12),
                radius: 14,
                onTap: () => openReviewDetails(review),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          statusTone(status).icon,
                          size: 16,
                          color: statusTone(status).fg,
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
                          label: status,
                          tone: statusTone(status),
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
                    if (canAmend) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _showAmendDecisionDialog(review),
                          style: TextButton.styleFrom(
                            foregroundColor: status == 'Approved'
                                ? AppTheme.danger
                                : AppTheme.tealText,
                          ),
                          icon: const Icon(Icons.undo_rounded, size: 15),
                          label: Text(
                            status == 'Approved'
                                ? 'Revoke / switch (${_formatAmendRemaining(review)})'
                                : 'Amend / switch (${_formatAmendRemaining(review)})',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
