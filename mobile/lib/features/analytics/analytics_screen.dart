import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  String get _report {
    final data = _data;
    if (data == null) return '';
    return 'BrandGuard report\nUser: ${session.currentUser?.email}\nGenerated: ${data['updated_at']}\nScope: ${session.currentUser?.isReviewer == true ? "Reviewer — all accessible checks" : "Creator — own checks only"}\n\nTotal checks: ${data['total_checks']}\nPending: ${data['pending']}\nApproved: ${data['approved']}\nRejected: ${data['rejected']}\nDetections: ${data['total_findings']}\nScans without detections: ${data['scan_passed']}\n\nFinding counts:\n${(data['rule_counts'] as Map? ?? {}).entries.map((e) => '${e.key}: ${e.value}').join('\n')}\n\nA scan without findings is not human approval or a guarantee of factual accuracy.';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson('/api/v1/analytics');
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report copied to clipboard.')),
      );
    }
  }

  int _num(String key) => (_data?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final total = _num('total_checks');
    final approved = _num('approved');
    final ruleCounts = (_data?['rule_counts'] as Map?) ?? const {};
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Analytics & reports'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh report',
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
            children: [
              const PageIntro(
                eyebrow: 'LIVE BACKEND DATA',
                title: 'Governance analytics',
                subtitle: 'Current versions and their latest review states — no sample metrics.',
              ),
              const SizedBox(height: 16),
              if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_data == null)
                const LoadingBlock(label: 'Calculating live metrics…')
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Total checks',
                        value: '$total',
                        tone: Tone.navy,
                        icon: Icons.folder_copy_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        label: 'Pending',
                        value: '${_num('pending')}',
                        tone: Tone.warning,
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Approved',
                        value: '$approved',
                        tone: Tone.success,
                        icon: Icons.verified_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: MetricCard(
                        label: 'Rejected',
                        value: '${_num('rejected')}',
                        tone: Tone.danger,
                        icon: Icons.cancel_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('APPROVAL RATIO', style: AppTheme.monoLabel()),
                      const SizedBox(height: 8),
                      ProgressLine(
                        value: total == 0 ? 0 : approved / total,
                        caption: total == 0
                            ? 'No checks recorded yet.'
                            : '$approved of $total checks currently approved.',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _smallStat(
                              'Detections',
                              '${_num('total_findings')}',
                              AppTheme.danger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _smallStat(
                              'Clean scans',
                              '${_num('scan_passed')}',
                              AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _smallStat(
                              'Rule types hit',
                              '${ruleCounts.length}',
                              AppTheme.info,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeading(
                  title: 'Finding counts by rule',
                  caption: 'Deterministic + model-assisted detections',
                ),
                const SizedBox(height: 8),
                if (ruleCounts.isEmpty)
                  const EmptyStateCard(
                    title: 'No findings recorded',
                    message: 'Rule counts appear here once a check produces a detection.',
                    icon: Icons.rule_rounded,
                  )
                else
                  SurfaceCard(
                    child: Column(
                      children: [
                        for (final entry in ruleCounts.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key.toString(),
                                    style: AppTheme.labelMedium.copyWith(
                                      fontSize: 12,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  label: '${entry.value}',
                                  tone: Tone.warning,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const SectionHeading(
                  title: 'Full report',
                  caption: 'Copyable, scope-labelled plain text',
                ),
                const SizedBox(height: 8),
                SurfaceCard(
                  child: SelectableText(
                    _report,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.ink,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Copy report'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'A scan without findings is not human approval or a guarantee of factual accuracy.',
                  textAlign: TextAlign.center,
                  style: AppTheme.monoLabel().copyWith(fontSize: 9.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTheme.tabular(18, FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.monoLabel().copyWith(fontSize: 8.5),
          ),
        ],
      ),
    );
  }
}
