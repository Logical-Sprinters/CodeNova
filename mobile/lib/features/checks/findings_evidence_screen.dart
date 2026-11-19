import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
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
  final Map<String, dynamic>? visualAnalysis;
  final List<Map<String, dynamic>> sourceConflicts;
  final List<dynamic> findings;

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
    this.visualAnalysis,
    this.sourceConflicts = const [],
  });

  @override
  State<FindingsEvidenceScreen> createState() => _FindingsEvidenceScreenState();
}

class _FindingsEvidenceScreenState extends State<FindingsEvidenceScreen> {
  String selectedFilter = 'All Findings';

  bool submitted = false;
  bool isSubmitting = false;

  late String _currentContent;

  // Stores replacements already applied to the original content.
  final Map<String, Map<String, dynamic>> _appliedReplacements = {};

  @override
  void initState() {
    super.initState();
    _currentContent = widget.contentText;
  }

  String get updatedContent => _currentContent;

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _findingKey(Map<String, dynamic> finding) {
    return '${finding['rule_id']}_${finding['start_index']}_${finding['end_index']}';
  }

  void applySuggestion(Map<String, dynamic> finding) {
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

    // Calculate how previous replacements shifted this phrase.
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

  Future<void> submitForReview() async {
    if (submitted || isSubmitting) return;

    setState(() {
      isSubmitting = true;
    });

    try {
      // Submit the updated content to the real backend.
      final response = await BrandGuardApiService.submitEditedContent(
        checkId: widget.checkId,
        expectedVersion: widget.contentVersion,
        content: updatedContent,
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
    return widget.findings
        .whereType<Map>()
        .map((finding) => Map<String, dynamic>.from(finding))
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

  int get _visualFindingCount {
    final violations = widget.visualAnalysis?['violations'];
    return violations is List ? violations.length : 0;
  }

  int get _totalFindingCount => widget.findings.length + _visualFindingCount;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
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
              label: '$_totalFindingCount findings',
              tone: _totalFindingCount == 0 ? Tone.success : Tone.danger,
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
                          '${widget.brandName} · check ${_shortId(widget.checkId)}',
                          style: AppTheme.monoLabel(color: AppTheme.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statusCard(),
                  if (widget.sourceConflicts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sourceConflictCard(),
                  ],
                  if (widget.visualAnalysis != null) ...[
                    const SizedBox(height: 12),
                    _visualAnalysisCard(),
                  ],
                  const SizedBox(height: 12),
                  _aiStatus(),
                  const SizedBox(height: 14),
                  _filterRow(),
                  const SizedBox(height: 12),
                  if (_visibleFindings.isEmpty)
                    EmptyStateCard(
                      title: widget.findings.isEmpty
                          ? _visualFindingCount == 0
                                ? 'No rule violations detected'
                                : 'No text rule violations detected'
                          : 'Nothing in this category',
                      message: widget.findings.isEmpty
                          ? _visualFindingCount == 0
                                ? 'The deterministic rules returned no findings for this exact text. This is not human approval — an authorised reviewer still has to decide.'
                                : 'Visual findings are shown in the evidence panel above. This is not human approval — an authorised reviewer still has to decide.'
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

  String _shortId(String value) {
    if (value.length <= 8) return value;
    return value.substring(0, 8);
  }

  Widget _statusCard() {
    final count = _totalFindingCount;
    final partial = widget.visualAnalysis?['status'] == 'partial';
    final clean = count == 0 && !partial;
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
                  color: clean
                      ? AppTheme.successBg
                      : partial
                      ? AppTheme.warningBg
                      : AppTheme.dangerBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  clean
                      ? Icons.task_alt_rounded
                      : partial
                      ? Icons.manage_search_rounded
                      : Icons.gpp_bad_rounded,
                  size: 17,
                  color: clean
                      ? AppTheme.success
                      : partial
                      ? AppTheme.warning
                      : AppTheme.danger,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.status == 'review_required'
                      ? 'Review required'
                      : widget.status == 'review_paused'
                      ? 'Review paused'
                      : 'Brand check complete',
                  maxLines: 2,
                  style: AppTheme.titleMedium.copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: StatusPill(
                  label: clean
                      ? 'Clear'
                      : partial && count == 0
                      ? 'Partial analysis'
                      : '$count findings',
                  tone: clean
                      ? Tone.success
                      : partial && count == 0
                      ? Tone.warning
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
                          text: 'No aggregate score: ',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: 'every finding needs evidence-backed resolution or authorised sign-off before publication.',
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

  Widget _sourceConflictCard() {
    final conflict = widget.sourceConflicts.first;
    final evidence = (conflict['evidence'] as List? ?? []);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InlineNotice(
            tone: Tone.warning,
            title: 'REVIEW PAUSED — SOURCE CONFLICT',
            message:
                'Conflicting company information was detected. Approval cannot continue until an authorized reviewer resolves it.',
          ),
          const SizedBox(height: 12),
          Text(
            'Topic: ${conflict['topic_key']}',
            style: AppTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...evidence.whereType<Map>().map((item) {
            final map = Map<String, dynamic>.from(item);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      map['title']?.toString() ?? 'Source',
                      style: AppTheme.titleMedium.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Normalized value: ${map['normalized_value']}',
                      style: AppTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      map['original_clause']?.toString() ?? '',
                      style: AppTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _visualAnalysisCard() {
    final analysis = widget.visualAnalysis!;
    final ocr = analysis['ocr'] is Map
        ? Map<String, dynamic>.from(analysis['ocr'] as Map)
        : <String, dynamic>{};
    final colors = analysis['colors'] is Map
        ? Map<String, dynamic>.from(analysis['colors'] as Map)
        : <String, dynamic>{};
    final logo = analysis['logo'] is Map
        ? Map<String, dynamic>.from(analysis['logo'] as Map)
        : <String, dynamic>{};
    final violations = analysis['violations'] as List? ?? [];
    final dominant = colors['dominant_colors'] as List? ?? [];
    final ocrBlocks = ocr['blocks'] as List? ?? [];
    String label(Object? value) =>
        (value?.toString() ?? 'not_configured').replaceAll('_', ' ');
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Visual evidence', style: AppTheme.titleMedium),
          const SizedBox(height: 10),
          _visualStatusRow(
            'Overall visual analysis',
            label(analysis['status']),
          ),
          _visualStatusRow('OCR', label(ocr['status'])),
          if (ocr['status'] == 'unavailable' && ocr['reason'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(ocr['reason'].toString(), style: AppTheme.bodySmall),
            ),
          _visualStatusRow(
            'Brand colors',
            colors['violations'] is List &&
                    (colors['violations'] as List).isNotEmpty
                ? '${label(colors['status'])} · ${(colors['violations'] as List).length} findings'
                : label(colors['status']),
          ),
          _visualStatusRow('Logo', label(logo['status'])),
          if (dominant.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Dominant HEX colors', style: AppTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final item in dominant.whereType<Map>())
                  StatusPill(
                    label:
                        '${item['hex']} · ${((item['share'] as num?)?.toDouble() ?? 0) * 100 ~/ 1}%',
                    tone: item['approved'] == false
                        ? Tone.danger
                        : item['approved'] == true
                        ? Tone.success
                        : Tone.neutral,
                    compact: true,
                  ),
              ],
            ),
          ],
          if (violations.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final violation in violations.whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InlineNotice(
                  tone: Tone.warning,
                  icon: Icons.warning_amber_rounded,
                  title: '${violation['rule_id']}: ${violation['message']}',
                  message: [
                    violation['evidence'],
                    if (violation['location'] is Map)
                      'Image region: x=${violation['location']['x']}, '
                          'y=${violation['location']['y']}, '
                          'w=${violation['location']['width']}, '
                          'h=${violation['location']['height']}',
                    violation['suggestion'],
                  ].where((value) => value != null).join('\n'),
                ),
              ),
          ],
          if (ocrBlocks.isNotEmpty ||
              ocr['text']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('OCR extracted text'),
              children: [
                if (ocrBlocks.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(ocr['text'].toString()),
                  )
                else ...[
                  for (final block in ocrBlocks.take(80).whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(block['text'].toString()),
                          ),
                          Text(
                            'Image region: x=${block['x']}, y=${block['y']} · '
                            'confidence ${(((block['confidence'] as num?)?.toDouble() ?? 0) * 100).round()}%',
                            style: AppTheme.monoLabel().copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  if (ocrBlocks.length > 80)
                    Text(
                      '${ocrBlocks.length - 80} additional OCR blocks omitted.',
                      style: AppTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Image SHA-256: ${analysis['image_sha256'] ?? 'unavailable'}',
            style: AppTheme.monoLabel().copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _visualStatusRow(String name, String status) {
    final skipped = status == 'not configured' || status == 'unavailable';
    final failed = status.contains('deprecated') || status.contains('finding');
    final partial = status == 'partial';
    final checked = status == 'complete' || status == 'approved detected';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(name, style: AppTheme.bodyMedium)),
          StatusPill(
            label: status,
            tone: skipped
                ? Tone.neutral
                : failed
                ? Tone.danger
                : partial
                ? Tone.warning
                : checked
                ? Tone.success
                : Tone.neutral,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _aiStatus() {
    final ai = widget.aiVerification;
    final status = ai?['status']?.toString();
    // The title intentionally embeds the raw server status so the UI can never
    // overstate what the AI layer actually did.
    final Tone tone = switch (status) {
      'completed' || 'match' => Tone.success,
      'abstained' || 'needs_review' => Tone.warning,
      null => Tone.neutral,
      _ => Tone.info,
    };
    final title = 'AI comparison: ${status ?? 'not supplied'}';
    final citations = ai?['citations'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineNotice(
          tone: tone,
          title: title,
          message: ai?['message']?.toString() ?? 'Open the protected processing receipt for this check’s comparison status.',
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
    final evidence = finding['evidence']?.toString() ?? '';
    final suggestion = finding['suggestion']?.toString() ?? '';
    final replacement = finding['replacement']?.toString() ?? '';
    final ruleId = finding['rule_id']?.toString() ?? 'UNKNOWN';
    final severity = finding['severity']?.toString() ?? 'review';
    final message = finding['message']?.toString() ?? '';
    final start = finding['start_index']?.toString() ?? '';
    final end = finding['end_index']?.toString() ?? '';
    final tone = _severityTone(severity);

    final key = _findingKey(finding);
    final isApplied = _appliedReplacements.containsKey(key);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(
                  label: severity,
                  tone: tone,
                  solid: true,
                  icon: tone.icon,
                  compact: true,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ruleId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.monoLabel(color: AppTheme.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppTheme.labelLarge.copyWith(fontSize: 13.5, height: 1.35),
            ),
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
            if (replacement.isNotEmpty) ...[
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
            const SizedBox(height: 8),
            Text(
              ruleId.startsWith('AI-')
                  ? 'Model-assisted comparison against cited evidence; review before relying on it.'
                  : 'Detected by the deterministic BrandGuard rule engine.',
              style: AppTheme.monoLabel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction() {
    final availableSuggestions = _backendFindings
        .where(
          (finding) => (finding['replacement']?.toString() ?? '').isNotEmpty,
        )
        .length;

    final appliedCount = _appliedReplacements.length;

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
                  'Reviewer decision required',
                  style: AppTheme.monoLabel(color: AppTheme.danger),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: (submitted || isSubmitting) ? null : submitForReview,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.teal),
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
                          const Icon(Icons.verified_user_outlined, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              submitted
                                  ? 'Submission processed'
                                  : 'Submit for authorised review',
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
