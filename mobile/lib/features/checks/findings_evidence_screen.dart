import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class FindingsEvidenceScreen extends StatefulWidget {
  final String contentText;
  final ValueChanged<String> onContentUpdated;

  final String checkId;
  final String brandName;
  final String status;
  final String? receiptId;
  final int? contentVersion;
  final Map<String, dynamic>? aiVerification;
  final List<dynamic> findings;
  final List<dynamic> conflicts;
  final String ocrText;
  final List<dynamic> visualSummary;
  final List<String> assetIds;
  final String channel;
  final String? checkAt;

  const FindingsEvidenceScreen({
    super.key,
    required this.contentText,
    required this.onContentUpdated,
    required this.checkId,
    required this.brandName,
    required this.status,
    required this.findings,
    this.receiptId,
    this.contentVersion,
    this.aiVerification,
    this.conflicts = const [],
    this.ocrText = '',
    this.visualSummary = const [],
    this.assetIds = const [],
    this.channel = 'all',
    this.checkAt,
  });

  @override
  State<FindingsEvidenceScreen> createState() => _FindingsEvidenceScreenState();
}

class _FindingsEvidenceScreenState extends State<FindingsEvidenceScreen> {
  static const List<(String, String, String)> _overrideReasons = [
    ('FALSE_POSITIVE', 'False positive', 'Rule matched harmless or unrelated phrasing'),
    ('APPROVED_EXCEPTION', 'Approved exception', 'Executive or legal pre-approved exception'),
    ('AMBIGUOUS_RULE_TEXT', 'Ambiguous rule text', 'Rule wording is unclear for this edge case'),
    ('OUTDATED_RULE_OR_FACT', 'Outdated rule/fact', 'Rule or fact appears stale vs current policy'),
    ('CONTEXTUAL_QUALIFIER', 'Contextual qualifier', 'Required disclaimer or qualifier is nearby'),
    ('CHANNEL_EXEMPTION', 'Channel exemption', 'Rule does not apply cleanly to this channel'),
  ];

  String selectedFilter = 'All Findings';

  bool submitted = false;
  bool isSubmitting = false;

  late String _currentContent;
  late String _status;
  late List<dynamic> _findings;
  late List<dynamic> _conflicts;

  // Stores replacements already applied to the original content.
  final Map<String, Map<String, dynamic>> _appliedReplacements = {};
  final Map<String, Map<String, dynamic>> _localOverrides = {};

  @override
  void initState() {
    super.initState();
    _currentContent = widget.contentText;
    _status = widget.status;
    _findings = List<dynamic>.from(widget.findings);
    _conflicts = List<dynamic>.from(widget.conflicts);
  }

  String get updatedContent => _currentContent;

  bool get _hasContentEdits => _currentContent != widget.contentText;

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _findingKey(Map<String, dynamic> finding) {
    return '${finding['finding_id'] ?? ''}_${finding['rule_id']}_${finding['start_index']}_${finding['end_index']}';
  }

  void applySuggestion(Map<String, dynamic> finding) {
    if ((finding['source_origin']?.toString() ?? 'caption') != 'caption') {
      showMessage('This finding is from image OCR/visual inspection — update the banner asset to resolve it.');
      return;
    }

    final evidence = finding['evidence']?.toString() ?? '';
    final replacement = finding['replacement']?.toString() ?? '';

    final startPoint = int.tryParse(finding['start_index']?.toString() ?? '');
    final endPoint = int.tryParse(finding['end_index']?.toString() ?? '');
    int nativeOffset(int point) => widget.contentText.runes
        .take(point)
        .fold(0, (length, rune) => length + (rune > 0xFFFF ? 2 : 1));
    final start = startPoint == null ? null : nativeOffset(startPoint);
    final end = endPoint == null ? null : nativeOffset(endPoint);

    final key = _findingKey(finding);

    if (_appliedReplacements.containsKey(key)) {
      showMessage('This suggestion has already been applied.');
      return;
    }

    if (evidence.isEmpty ||
        replacement.isEmpty ||
        start == null ||
        end == null) {
      showMessage('A valid replacement or content position is missing.');
      return;
    }

    int shift = 0;

    for (final applied in _appliedReplacements.values) {
      final appliedEnd = applied['end'] as int;
      final appliedEvidence = applied['evidence'] as String;
      final appliedReplacement = applied['replacement'] as String;

      if (appliedEnd <= start) {
        shift += appliedReplacement.length - appliedEvidence.length;
      } else if ((applied['start'] as int) < end) {
        showMessage('This finding overlaps an already applied replacement.');
        return;
      }
    }

    final adjustedStart = start + shift;
    final adjustedEnd = adjustedStart + evidence.length;

    if (adjustedStart < 0 ||
        adjustedEnd > _currentContent.length ||
        _currentContent.substring(adjustedStart, adjustedEnd) != evidence) {
      showMessage(
        'Could not safely locate the original phrase. Please recheck the content.',
      );
      return;
    }

    setState(() {
      _currentContent = _currentContent.replaceRange(
        adjustedStart,
        adjustedEnd,
        replacement,
      );

      _appliedReplacements[key] = {
        'start': start,
        'end': end,
        'evidence': evidence,
        'replacement': replacement,
      };
    });

    widget.onContentUpdated(_currentContent);
    showMessage('Suggestion applied successfully.');
  }

  Future<void> _openOverrideDialog(Map<String, dynamic> finding) async {
    final findingId = finding['finding_id']?.toString() ?? '';
    if (findingId.isEmpty) {
      showMessage('Finding ID missing.');
      return;
    }
    var selectedReason = _overrideReasons.first.$1;
    final noteCtrl = TextEditingController();
    var busy = false;
    String? dlgError;

    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Override finding (coded reason)'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a coded governance reason for overriding ${finding['rule_id']}. Repeated overrides open a Clarity Ticket without mutating rules.',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 10),
                  for (final item in _overrideReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(9),
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
                              size: 16,
                              color: selectedReason == item.$1
                                  ? AppTheme.teal
                                  : AppTheme.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$2,
                                    style: AppTheme.labelMedium.copyWith(
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  Text(item.$3, style: AppTheme.bodySmall),
                                ],
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
                      labelText: 'Reviewer note (optional)',
                      hintText: 'Context for clarity telemetry...',
                    ),
                  ),
                  if (dlgError != null) ...[
                    const SizedBox(height: 8),
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
                        final data = await BrandGuardApiService.overrideFinding(
                          checkId: widget.checkId,
                          findingId: findingId,
                          reasonCode: selectedReason,
                          note: noteCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, data);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() {
                            busy = false;
                            dlgError = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving...' : 'Log override'),
            ),
          ],
        ),
      ),
    );
    try {
      final res = await Navigator.of(context).push(route);

      if (res != null && mounted) {
        setState(() {
          _localOverrides[findingId] = {
            'reason_code': selectedReason,
            'note': noteCtrl.text.trim(),
          };
        });
        final ticketOpened = res['clarity_ticket'] != null;
        showMessage(
          ticketOpened
              ? 'Override logged ($selectedReason) — Clarity Ticket opened for guideline owner!'
              : 'Override logged ($selectedReason).',
        );
      }
    } finally {
      await route.completed;
      noteCtrl.dispose();
    }
  }

  Future<void> _resolveConflictDialog(Map<String, dynamic> conflict) async {
    final clauses = (conflict['clauses'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    if (clauses.isEmpty) return;

    var selectedIdx = 0;
    final noteCtrl = TextEditingController();
    var busy = false;
    String? dlgError;

    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Resolve & pin active rule'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Topic "${conflict['topic_key']}" has contradictory active sources. Choose the authoritative rule or fact:',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < clauses.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(10),
                        radius: 10,
                        borderColor: selectedIdx == i
                            ? AppTheme.teal
                            : AppTheme.border,
                        color: selectedIdx == i
                            ? AppTheme.mint
                            : AppTheme.card,
                        onTap: () => setDlg(() => selectedIdx = i),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              selectedIdx == i
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: selectedIdx == i
                                  ? AppTheme.teal
                                  : AppTheme.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${clauses[i]['source_type']?.toString().toUpperCase()} · ${clauses[i]['source_id']} (${clauses[i]['canonical_value'] ?? ''})',
                                    style: AppTheme.labelMedium.copyWith(
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    clauses[i]['excerpt']?.toString() ?? '',
                                    style: AppTheme.bodySmall,
                                  ),
                                ],
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
                      labelText: 'Resolution note',
                    ),
                  ),
                  if (dlgError != null) ...[
                    const SizedBox(height: 8),
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
                        final winner = clauses[selectedIdx];
                        final data = await BrandGuardApiService.resolveConflict(
                          conflictId: conflict['conflict_id'].toString(),
                          winningSourceType: winner['source_type'].toString(),
                          winningSourceId: winner['source_id'].toString(),
                          resolutionNote: noteCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, data);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() {
                            busy = false;
                            dlgError = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Pinning...' : 'Pin winner & recheck'),
            ),
          ],
        ),
      ),
    );
    try {
      final result = await Navigator.of(context).push(route);

      if (result != null && mounted) {
        setState(() {
          _conflicts = [];
          _status = 'review_required';
        });
        showMessage('Conflict resolved! Check unlocked and re-evaluated.');
      }
    } finally {
      await route.completed;
      noteCtrl.dispose();
    }
  }

  Future<void> submitForReview() async {
    if (submitted || isSubmitting) return;

    setState(() {
      isSubmitting = true;
    });

    try {
      final response = await BrandGuardApiService.submitEditedContent(
        checkId: widget.checkId,
        expectedVersion: widget.contentVersion,
        content: updatedContent,
        assetIds: widget.assetIds.isEmpty ? null : widget.assetIds,
        channel: widget.channel == 'all' ? null : widget.channel,
        checkAt: widget.checkAt,
      );

      final checkId = response['check_id']?.toString() ?? 'N/A';
      final receiptId = response['receipt_id']?.toString() ?? 'N/A';
      final status = response['status']?.toString() ?? 'unknown';

      widget.onContentUpdated(updatedContent);

      if (!mounted) return;

      setState(() {
        submitted = true;
        isSubmitting = false;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: Icon(
              Icons.fact_check_rounded,
              color: AppTheme.teal,
              size: 40,
            ),
            title: const Text('Submission processed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'The updated content was stored as a new version and is now waiting for an authorised reviewer.',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                _submissionInfo('CHECK ID', checkId),
                const SizedBox(height: 8),
                _submissionInfo('RECEIPT ID', receiptId),
                const SizedBox(height: 8),
                _submissionInfo('BACKEND STATUS', status.toUpperCase()),
                const SizedBox(height: 12),
                Text(
                  'Final approval must come from an authorised reviewer.',
                  style: AppTheme.monoLabel(),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.popUntil((route) => route.isFirst);
                    navigator.pushNamed('/receiptDetail', arguments: receiptId);
                  },
                  child: const Text('View receipt'),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      showMessage('Submission failed: $e');
    }
  }

  Widget _submissionInfo(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: AppTheme.monoLabel()),
          const SizedBox(height: 4),
          SelectableText(
            value,
            textAlign: TextAlign.center,
            style: AppTheme.monoLabel(color: AppTheme.tealText)
                .copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _backendFindings {
    return _findings
        .whereType<Map>()
        .map((finding) => Map<String, dynamic>.from(finding))
        .toList();
  }

  List<Map<String, dynamic>> get _conflictList {
    return _conflicts
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
  }

  List<String> get _filters {
    final severities = _backendFindings
        .map((f) => f['severity']?.toString().toLowerCase() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    return [
      'All Findings',
      for (final severity in ['critical', 'review', 'warning'])
        if (severities.contains(severity))
          severity[0].toUpperCase() + severity.substring(1),
    ];
  }

  List<Map<String, dynamic>> get _visibleFindings {
    if (selectedFilter == 'All Findings') return _backendFindings;
    return _backendFindings
        .where(
          (f) =>
              (f['severity']?.toString().toLowerCase() ?? '') ==
              selectedFilter.toLowerCase(),
        )
        .toList();
  }

  Color? _parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final val = int.tryParse(cleaned, radix: 16);
    if (val == null) return null;
    return Color(0xFF000000 | val);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final isConflict =
        _status == 'review_paused_conflict' || _conflictList.isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Audit inspection'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StatusPill(
              label: isConflict ? 'Paused' : '${_findings.length} findings',
              tone: isConflict
                  ? Tone.warning
                  : _findings.isEmpty
                  ? Tone.success
                  : Tone.danger,
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 15,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${widget.brandName} · check ${_shortId(widget.checkId)} · ${widget.channel}',
                          style: AppTheme.monoLabel(color: AppTheme.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isConflict) ...[
                    _conflictEscalationSection(),
                    const SizedBox(height: 12),
                  ],
                  _statusCard(isConflict),
                  const SizedBox(height: 12),
                  _aiStatus(),
                  if (widget.ocrText.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      radius: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IMAGE OCR TEXT FUSED INTO CHECK',
                            style: AppTheme.monoLabel(color: AppTheme.info),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            widget.ocrText,
                            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _filterRow(),
                  const SizedBox(height: 12),
                  if (isConflict)
                    const EmptyStateCard(
                      title: 'Review paused — conflict abstention',
                      message: 'BrandGuard abstained from emitting guessed findings while internal policies disagree. Resolve the conflict above first.',
                      icon: Icons.balance_rounded,
                    )
                  else if (_visibleFindings.isEmpty)
                    EmptyStateCard(
                      title: _findings.isEmpty
                          ? 'No rule violations detected'
                          : 'Nothing in this category',
                      message: _findings.isEmpty
                          ? 'The deterministic rules returned no findings for this exact text. This is not human approval — an authorised reviewer still has to decide.'
                          : 'Switch the filter to see the other findings on this check.',
                      icon: Icons.task_alt_rounded,
                    )
                  else
                    ..._visibleFindings.map(_backendFindingCard),
                ],
              ),
            ),
            _bottomAction(),
          ],
        ),
      ),
    );
  }

  Widget _conflictEscalationSection() {
    final isReviewer = session.currentUser?.isReviewer ?? false;
    return Column(
      children: _conflictList.map((conflict) {
        final clauses = (conflict['clauses'] as List? ?? [])
            .whereType<Map>()
            .map((c) => Map<String, dynamic>.from(c))
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceCard(
            borderColor: AppTheme.warning.withValues(alpha: 0.55),
            color: AppTheme.warningBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'REVIEW PAUSED — INTERNAL RULE CONFLICT',
                        style: AppTheme.labelLarge.copyWith(
                          color: AppTheme.navyDeep,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Topic "${conflict['topic_key'] ?? 'policy'}" has conflicting active sources:',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 520 && clauses.length >= 2;
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < clauses.length; i++) ...[
                            Expanded(child: _conflictClauseCard(clauses[i])),
                            if (i != clauses.length - 1) const SizedBox(width: 8),
                          ],
                        ],
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < clauses.length; i++) ...[
                          _conflictClauseCard(clauses[i]),
                          if (i != clauses.length - 1) const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
                if (isReviewer) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _resolveConflictDialog(conflict),
                      icon: const Icon(Icons.gavel_rounded, size: 16),
                      label: const Text('Resolve & Pin Active Rule'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _conflictClauseCard(Map<String, dynamic> clause) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${clause['source_type']?.toString().toUpperCase()} · ${clause['source_id']} v${clause['version'] ?? '1.0.0'}',
            style: AppTheme.monoLabel(color: AppTheme.tealText),
          ),
          const SizedBox(height: 3),
          Text(
            clause['title']?.toString() ?? '',
            style: AppTheme.labelMedium.copyWith(color: AppTheme.ink),
          ),
          if ((clause['canonical_value']?.toString() ?? '').isNotEmpty)
            Text(
              'Value: ${clause['canonical_value']}',
              style: AppTheme.monoLabel(color: AppTheme.danger),
            ),
          const SizedBox(height: 4),
          Text(
            clause['excerpt']?.toString() ?? '',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
          ),
        ],
      ),
    );
  }

  String _shortId(String value) {
    if (value.length <= 8) return value;
    return value.substring(0, 8);
  }

  Widget _statusCard(bool isConflict) {
    final count = _findings.length;
    final clean = count == 0 && !isConflict;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isConflict
                      ? AppTheme.warningBg
                      : clean
                      ? AppTheme.successBg
                      : AppTheme.dangerBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isConflict
                      ? Icons.balance_rounded
                      : clean
                      ? Icons.task_alt_rounded
                      : Icons.gpp_bad_rounded,
                  size: 17,
                  color: isConflict
                      ? AppTheme.warning
                      : clean
                      ? AppTheme.success
                      : AppTheme.danger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isConflict
                      ? 'Review paused on conflict'
                      : _status == 'review_required'
                      ? 'Review required'
                      : 'Brand check complete',
                  maxLines: 2,
                  style: AppTheme.titleMedium.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: StatusPill(
                  label: isConflict
                      ? 'Abstained'
                      : clean
                      ? 'Clear'
                      : '$count findings',
                  tone: isConflict
                      ? Tone.warning
                      : clean
                      ? Tone.success
                      : Tone.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.policy_outlined, size: 16, color: AppTheme.navy),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                      children: const [
                        TextSpan(
                          text: 'No finding without evidence: ',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: 'every finding carries its active rule version and verbatim stored rule quote.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiStatus() {
    final ai = widget.aiVerification;
    final status = ai?['status']?.toString();
    final Tone tone = switch (status) {
      'completed' || 'match' || 'supported' => Tone.success,
      'abstained' || 'needs_review' => Tone.warning,
      null => Tone.neutral,
      _ => Tone.info,
    };
    final title = 'AI comparison: ${status ?? 'not supplied'}';
    final rawMsg = ai?['message']?.toString().trim();
    final friendlyFallback =
        'Open the protected processing receipt for this check’s comparison status.';
    final displayMessage = (status == 'abstained' &&
            rawMsg != null &&
            rawMsg.isNotEmpty &&
            !rawMsg.toLowerCase().contains('rule checks'))
        ? '$rawMsg What this means: AI fact-checking did not run right now, so BrandGuard made no AI guess — your standard brand rule checks still ran.'
        : (rawMsg?.isNotEmpty == true ? rawMsg! : friendlyFallback);
    final citations = ai?['citations'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNotice(
          tone: tone,
          title: title,
          message: displayMessage,
        ),
        if (citations is List && citations.isNotEmpty) ...[
          const SizedBox(height: 8),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            radius: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CITED EVIDENCE',
                  style: AppTheme.monoLabel(color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
                ...citations.whereType<Map>().map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(
                      '${c['title'] ?? c['fact_id']}\n“${c['quote'] ?? ''}”',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.receiptId != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(
              context,
              '/receiptDetail',
              arguments: widget.receiptId,
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: const Text('View processing receipt'),
          ),
        ],
      ],
    );
  }

  Widget _filterRow() {
    final filters = _filters;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final active = selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: GestureDetector(
              onTap: () => setState(() => selectedFilter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active ? AppTheme.mint : AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active ? AppTheme.teal : AppTheme.border,
                  ),
                ),
                child: Text(
                  filter,
                  style: AppTheme.labelMedium.copyWith(
                    fontSize: 11.5,
                    color: active ? AppTheme.tealText : AppTheme.ink,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Tone _severityTone(String severity) => switch (severity.toLowerCase()) {
    'critical' || 'high' => Tone.danger,
    'warning' || 'medium' => Tone.warning,
    _ => Tone.info,
  };

  Widget _backendFindingCard(Map<String, dynamic> finding) {
    final findingId = finding['finding_id']?.toString() ?? '';
    final evidence = finding['evidence']?.toString() ?? '';
    final suggestion = finding['suggestion']?.toString() ?? '';
    final replacement = finding['replacement']?.toString() ?? '';
    final ruleId = finding['rule_id']?.toString() ?? 'UNKNOWN';
    final ruleVersion = finding['rule_version']?.toString() ?? '1.0.0';
    final ruleQuote = finding['rule_quote']?.toString() ?? '';
    final sourceOrigin = finding['source_origin']?.toString() ?? 'caption';
    final severity = finding['severity']?.toString() ?? 'review';
    final message = finding['message']?.toString() ?? '';
    final start = finding['start_index']?.toString() ?? '';
    final end = finding['end_index']?.toString() ?? '';
    final visualEv = finding['visual_evidence'] is Map
        ? Map<String, dynamic>.from(finding['visual_evidence'] as Map)
        : null;
    final overrideInfo = _localOverrides[findingId] ??
        (finding['override'] is Map
            ? Map<String, dynamic>.from(finding['override'] as Map)
            : null);
    final isOverridden =
        finding['overridden'] == true || overrideInfo != null;
    final tone = _severityTone(severity);

    final key = _findingKey(finding);
    final isApplied = _appliedReplacements.containsKey(key);
    final isReviewer = session.currentUser?.isReviewer ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(
                  label: severity,
                  tone: tone,
                  solid: true,
                  icon: tone.icon,
                  compact: true,
                ),
                StatusPill(
                  label: '$ruleId · v$ruleVersion',
                  tone: Tone.navy,
                  compact: true,
                ),
                StatusPill(
                  label: sourceOrigin.replaceAll('_', ' '),
                  tone: Tone.info,
                  compact: true,
                ),
                if (isOverridden)
                  StatusPill(
                    label:
                        'Overridden (${overrideInfo?['reason_code'] ?? 'LOGGED'})',
                    tone: Tone.warning,
                    compact: true,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTheme.labelLarge.copyWith(fontSize: 13.5, height: 1.35),
            ),
            if (ruleQuote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VERBATIM RULE QUOTE',
                      style: AppTheme.monoLabel(color: AppTheme.tealText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '“$ruleQuote”',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.ink,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (visualEv != null) ...[
              const SizedBox(height: 10),
              _visualEvidenceBlock(visualEv),
            ],
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tone.fg.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MATCHED EVIDENCE · $start–$end',
                      style: AppTheme.monoLabel(color: tone.fg),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      evidence,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (suggestion.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'SUGGESTED ACTION',
                style: AppTheme.monoLabel(color: AppTheme.muted),
              ),
              const SizedBox(height: 3),
              Text(
                suggestion,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
              ),
            ],
            if (replacement.isNotEmpty && sourceOrigin == 'caption') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.successBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.success.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUGGESTED REPLACEMENT',
                      style: AppTheme.monoLabel(color: AppTheme.success),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      replacement,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: isApplied ? null : () => applySuggestion(finding),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.navy),
                  icon: Icon(
                    isApplied
                        ? Icons.check_rounded
                        : Icons.auto_fix_high_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isApplied ? 'Suggestion applied' : 'Apply suggestion',
                  ),
                ),
              ),
            ],
            if (finding['citations'] is List &&
                (finding['citations'] as List).isNotEmpty) ...[
              const SizedBox(height: 10),
              ...(finding['citations'] as List).whereType<Map>().map(
                (citation) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SelectableText(
                    'Source: ${citation['title'] ?? citation['fact_id']}\n${citation['source_url'] ?? ''}\n${citation['quote'] ?? ''}',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                ),
              ),
            ],
            if (isReviewer && !isOverridden && findingId.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openOverrideDialog(finding),
                  icon: const Icon(Icons.rule_folder_outlined, size: 16),
                  label: const Text('Override finding (coded reason)'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              ruleId.startsWith('AI-')
                  ? 'Model-assisted comparison against cited evidence; review before relying on it.'
                  : 'Grounded server-side against versioned BrandGuard rules.',
              style: AppTheme.monoLabel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _visualEvidenceBlock(Map<String, dynamic> visualEv) {
    final kind = visualEv['check']?.toString() ?? 'visual';
    if (kind == 'palette') {
      final hex = visualEv['detected_hex']?.toString() ?? '';
      final parsed = _parseHexColor(hex);
      final allowed = (visualEv['allowed_hex_colors'] as List? ?? [])
          .map((e) => e.toString())
          .toList();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.infoBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PALETTE EVIDENCE · ${visualEv['asset_name'] ?? 'Banner'}',
              style: AppTheme.monoLabel(color: AppTheme.info),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (parsed != null) ...[
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: parsed,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.borderStrong),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    'Detected $hex (${visualEv['coverage_pct'] ?? 0}% coverage)',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                ),
              ],
            ),
            if (allowed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: allowed.take(6).map((h) {
                  final c = _parseHexColor(h);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c != null) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(h, style: AppTheme.monoLabel().copyWith(fontSize: 9)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.dangerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOGO MATCH EVIDENCE · ${visualEv['asset_name'] ?? 'Banner'}',
            style: AppTheme.monoLabel(color: AppTheme.danger),
          ),
          const SizedBox(height: 4),
          Text(
            '${visualEv['label'] ?? 'Deprecated logo'} detected in ${visualEv['region'] ?? 'banner'} (${visualEv['similarity_pct'] ?? 0}% match)',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
          ),
        ],
      ),
    );
  }

  Widget _bottomAction() {
    final availableSuggestions = _backendFindings
        .where(
          (finding) =>
              (finding['source_origin']?.toString() ?? 'caption') == 'caption' &&
              (finding['replacement']?.toString() ?? '').isNotEmpty,
        )
        .length;

    final appliedCount = _appliedReplacements.length;
    final hasEdits = _hasContentEdits;
    final ver = widget.contentVersion ?? 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A142C3B),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Suggestions applied: $appliedCount of $availableSuggestions',
                  style: AppTheme.monoLabel(),
                ),
                Text(
                  submitted
                      ? 'v${ver + 1} queued'
                      : hasEdits
                      ? 'Edited · ready to resubmit'
                      : 'v$ver already queued',
                  style: AppTheme.monoLabel(
                    color: hasEdits ? AppTheme.tealText : AppTheme.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: (submitted || isSubmitting)
                    ? null
                    : hasEdits
                    ? submitForReview
                    : () => Navigator.maybePop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: hasEdits ? AppTheme.teal : AppTheme.navy,
                ),
                child: isSubmitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            submitted || !hasEdits
                                ? Icons.check_circle_outline_rounded
                                : Icons.verified_user_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              submitted
                                  ? 'Submission processed'
                                  : hasEdits
                                  ? 'Submit edited v${ver + 1} for review'
                                  : 'Queued as v$ver · Done',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
