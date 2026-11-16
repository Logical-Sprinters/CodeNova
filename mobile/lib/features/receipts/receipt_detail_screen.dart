import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';

/// Protected processing receipt: server-verified processing facts for one
/// content version. Only fields the backend actually returns are shown.
class ReceiptDetailScreen extends StatefulWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getReceipt(
        receiptId: widget.receiptId,
      );
      if (!mounted) return;
      setState(() => _receipt = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _receipt = {'error': e.toString()});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _short(Object? value, {int keep = 16}) {
    final text = value?.toString() ?? '—';
    if (text.length <= keep + 3) return text;
    return '${text.substring(0, keep)}…';
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final error = receipt?['error']?.toString();
    final ai = receipt?['ai_verification'] is Map
        ? Map<String, dynamic>.from(receipt!['ai_verification'] as Map)
        : const <String, dynamic>{};
    final approvalValid = receipt?['approval_valid'] == true;
    final currentVersion = receipt?['is_current_version'] == true;
    final rulesCurrent = receipt?['rules_current'] == true;
    final reviewStatus =
        receipt?['current_review_status']?.toString() ??
        receipt?['final_status']?.toString() ??
        'unknown';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Processing receipt'),
        actions: [
          IconButton(
            tooltip: 'Reload receipt',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const LoadingBlock(label: 'Verifying receipt with the server…')
            : error != null
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ErrorBlock(
                    title: 'Receipt could not be verified',
                    message: error,
                    onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    },
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 34, radius: 10),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cryptographic record',
                              style: AppTheme.labelLarge.copyWith(fontSize: 13),
                            ),
                            Text(
                              'Deterministic ledger record for audit compliance',
                              style: AppTheme.monoLabel(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'RECEIPT IDENTIFIER',
                              style: AppTheme.monoLabel(),
                            ),
                            const Spacer(),
                            StatusPill(
                              label: approvalValid ? 'Verified' : 'Recorded',
                              tone: approvalValid ? Tone.success : Tone.neutral,
                              icon: approvalValid
                                  ? Icons.verified_rounded
                                  : Icons.receipt_long_outlined,
                              solid: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          widget.receiptId,
                          style: AppTheme.monoLabel(color: AppTheme.tealText)
                              .copyWith(fontSize: 11.5),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 10),
                        Text('CONTENT ARTIFACT', style: AppTheme.monoLabel()),
                        const SizedBox(height: 6),
                        Text(
                          receipt?['brand_name']?.toString() ?? '—',
                          style: AppTheme.labelLarge.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            HashChip(
                              label: 'v${receipt?['content_version'] ?? '—'}',
                              value: _short(receipt?['content_hash'], keep: 12),
                              tone: Tone.navy,
                            ),
                            HashChip(
                              label: 'rules',
                              value: '${receipt?['rules_version'] ?? '—'}',
                              tone: rulesCurrent ? Tone.success : Tone.warning,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Timestamp: ${receipt?['timestamp'] ?? '—'}',
                          style: AppTheme.monoLabel(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCard(
                          label: 'Deterministic',
                          value: '${receipt?['deterministic_findings'] ?? 0}',
                          tone: Tone.navy,
                          icon: Icons.rule_rounded,
                          footnote:
                              'Engine ${receipt?['deterministic_engine'] ?? '—'}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MetricCard(
                          label: 'Scan status',
                          value: (receipt?['scan_status']?.toString() ?? '—')
                              .replaceAll('_', ' '),
                          tone: receipt?['scan_status'] == 'passed'
                              ? Tone.success
                              : Tone.warning,
                          icon: receipt?['scan_status'] == 'passed'
                              ? Icons.task_alt_rounded
                              : Icons.flag_rounded,
                          footnote: 'Rules only',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MetricCard(
                    label: 'Verification',
                    value: (receipt?['scan_status'] == 'passed')
                        ? 'No rule findings'
                        : 'Findings recorded',
                    tone: receipt?['scan_status'] == 'passed'
                        ? Tone.success
                        : Tone.danger,
                    icon: Icons.verified_rounded,
                    footnote: 'Rule engine outcome — not publication clearance',
                  ),
                  const SizedBox(height: 16),
                  const SectionHeading(
                    title: 'Review state',
                    caption: 'Current server-side decision',
                  ),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    child: Column(
                      children: [
                        DetailRow(
                          label: 'Current review',
                          value: reviewStatus.replaceAll('_', ' '),
                          valueColor: reviewStatus == 'approved'
                              ? AppTheme.success
                              : reviewStatus == 'rejected'
                              ? AppTheme.danger
                              : AppTheme.warning,
                        ),
                        DetailRow(
                          label: 'Receipt status',
                          value:
                              (receipt?['final_status']?.toString() ??
                                      'pending')
                                  .replaceAll('_', ' '),
                        ),
                        DetailRow(
                          label: 'Version current',
                          value: currentVersion ? 'Yes' : 'No — newer version',
                          valueColor: currentVersion
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                        DetailRow(
                          label: 'Rules current',
                          value: rulesCurrent ? 'Yes' : 'No — rules changed',
                          valueColor: rulesCurrent
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                        DetailRow(
                          label: 'Approval valid',
                          value: approvalValid
                              ? 'Bound to this exact content'
                              : 'Not an approval for this content',
                          valueColor: approvalValid
                              ? AppTheme.success
                              : AppTheme.muted,
                        ),
                        if (receipt?['reviewer'] != null)
                          DetailRow(
                            label: 'Reviewer',
                            value: receipt!['reviewer'].toString(),
                          ),
                        if (receipt?['decided_at'] != null)
                          DetailRow(
                            label: 'Decided',
                            value: receipt!['decided_at'].toString(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeading(title: 'Evidence grounding'),
                  const SizedBox(height: 8),
                  InlineNotice(
                    tone: ai['status'] == 'completed'
                        ? Tone.success
                        : ai['status'] == 'abstained'
                        ? Tone.warning
                        : Tone.info,
                    title: 'AI comparison: ${ai['status'] ?? 'not recorded'}',
                    message: ai['message']?.toString() ?? 'No AI comparison details were stored for this receipt. Deterministic rules ran independently of any model.',
                  ),
                  const SizedBox(height: 16),
                  const SectionHeading(title: 'Immutable receipt & notice'),
                  const SizedBox(height: 8),
                  const InlineNotice(
                    tone: Tone.info,
                    icon: Icons.lock_outline_rounded,
                    title: 'What this record proves',
                    message: 'It binds a content hash, a rules version and the review outcome as stored by the server. Zero unsupported claims are made: this is not legal clearance, a certification or proof of factual truth.',
                  ),
                  const SizedBox(height: 10),
                  SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RAW RECEIPT (SERVER RESPONSE)',
                          style: AppTheme.monoLabel(),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _pretty(receipt),
                          style: AppTheme.monoLabel(color: AppTheme.ink)
                              .copyWith(fontSize: 10.5, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _pretty(Map<String, dynamic>? data) {
    if (data == null) return '';
    final buffer = StringBuffer();
    data.forEach((key, value) {
      final rendered = value is Map || value is List
          ? value.toString()
          : value.toString();
      buffer.writeln('$key: $rendered');
    });
    return buffer.toString();
  }
}
