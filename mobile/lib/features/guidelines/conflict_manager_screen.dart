import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class ConflictManagerScreen extends StatefulWidget {
  const ConflictManagerScreen({super.key});

  @override
  State<ConflictManagerScreen> createState() => _ConflictManagerScreenState();
}

class _ConflictManagerScreenState extends State<ConflictManagerScreen> {
  List<Map<String, dynamic>> _conflicts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await BrandGuardApiService.getJson(
        '/api/v1/conflicts?brand_name=Acme&status=unresolved',
      );
      if (!mounted) return;
      setState(() {
        _conflicts = (data['conflicts'] as List? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> conflict) async {
    if (!(session.currentUser?.isReviewer ?? false)) return;
    final evidence = (conflict['evidence'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    String? selected = evidence.isNotEmpty
        ? evidence.first['fact_id']?.toString()
        : null;
    final reason = TextEditingController();
    final decision = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Resolve source conflict'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final source in evidence)
                    RadioListTile<String>(
                      value: source['fact_id'].toString(),
                      groupValue: selected,
                      title: Text(source['title']?.toString() ?? 'Source'),
                      subtitle: Text(
                        '${source['normalized_value']} · ${source['original_clause']}',
                        maxLines: 4,
                      ),
                      onChanged: (value) => update(() => selected = value),
                    ),
                  TextField(
                    controller: reason,
                    maxLines: 3,
                    onChanged: (_) => update(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Resolution reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: reason.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(dialog, {'keep_unresolved': true}),
              child: const Text('Keep unresolved'),
            ),
            FilledButton(
              onPressed: reason.text.trim().length < 3
                  ? null
                  : selected == null
                  ? null
                  : () => Navigator.pop(dialog, {'keep_unresolved': false}),
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
    final resolutionReason = reason.text.trim();
    reason.dispose();
    if (decision == null) return;
    try {
      await BrandGuardApiService.request(
        'POST',
        '/api/v1/conflicts/${Uri.encodeComponent(conflict['id'].toString())}/resolve',
        body: {
          'selected_fact_id': decision['keep_unresolved'] == true
              ? null
              : selected,
          'resolution_reason': resolutionReason,
        },
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Rule Conflict Manager')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const PageIntro(
                eyebrow: 'SOURCE AUTHORITY',
                eyebrowTone: Tone.warning,
                title: 'Resolve conflicting facts',
                subtitle: 'BrandGuard pauses affected reviews until an authorized reviewer selects one source or leaves the conflict unresolved.',
              ),
              const SizedBox(height: 12),
              if (_loading)
                const LoadingBlock(label: 'Loading source conflicts…')
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_conflicts.isEmpty)
                const EmptyStateCard(
                  title: 'No unresolved conflicts',
                  message: 'Current verified sources have no detected applicable disagreements.',
                  icon: Icons.verified_rounded,
                )
              else
                for (final conflict in _conflicts) ...[
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conflict['topic_key']?.toString() ?? 'Unknown topic',
                          style: AppTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...((conflict['evidence'] as List? ?? []).map((item) {
                          final source = Map<String, dynamic>.from(item as Map);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${source['title']} · ${source['department']} · ${source['effective_from'] ?? 'no start'} to ${source['effective_to'] ?? 'open'} · ${source['authority']}\n${source['normalized_value']} — ${source['original_clause']}',
                              style: AppTheme.bodyMedium,
                            ),
                          );
                        })),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _resolve(conflict),
                          icon: const Icon(Icons.gavel_rounded),
                          label: const Text('Resolve conflict'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
