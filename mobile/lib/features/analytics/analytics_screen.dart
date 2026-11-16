import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Analytics & Reports'),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Refresh report',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_data == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_data != null) ...[
            const Text(
              'Live backend data',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'This report contains current versions and their latest review states, not sample metrics. Pull to refresh.',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(_report),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: const Text('Copy Report'),
            ),
          ],
        ],
      ),
    ),
  );
}
