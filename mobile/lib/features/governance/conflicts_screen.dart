import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  String _filter = 'open';
  List<Map<String, dynamic>> _conflicts = [];
  bool _loading = true;
  String? _error;

  bool get _canManage => session.currentUser?.isReviewer ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await BrandGuardApiService.getConflicts();
      if (!mounted) return;
      setState(() {
        _conflicts = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    if (_filter == 'all') return _conflicts;
    return _conflicts
        .where((c) => (c['status']?.toString() ?? 'open') == _filter)
        .toList();
  }

  Future<void> _resolveDialog(Map<String, dynamic> conflict) async {
    final clauses = (conflict['clauses'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    if (clauses.isEmpty) return;

    var selectedIdx = 0;
    final noteCtrl = TextEditingController();
    var busy = false;
    String? dlgError;

    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Resolve & pin active rule'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select the winning source for topic "${conflict['topic_key']}". Losing contradictory sources will be superseded.',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < clauses.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(10),
                        radius: 12,
                        borderColor: selectedIdx == i
                            ? AppTheme.teal
                            : AppTheme.border,
                        color: selectedIdx == i
                            ? AppTheme.mint
                            : AppTheme.card,
                        onTap: () => setDlg(() => selectedIdx = i),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${clauses[i]['source_type']?.toString().toUpperCase()} · ${clauses[i]['source_id']} (${clauses[i]['canonical_value'] ?? ''})',
                                    style: AppTheme.labelMedium.copyWith(
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              clauses[i]['excerpt']?.toString() ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodySmall,
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
                      hintText: 'Explain why this policy takes precedence...',
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
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
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
                        await BrandGuardApiService.resolveConflict(
                          conflictId: conflict['conflict_id'].toString(),
                          winningSourceType: winner['source_type'].toString(),
                          winningSourceId: winner['source_id'].toString(),
                          resolutionNote: noteCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
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
      final resolved = await Navigator.of(context).push(route);
      if (resolved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conflict resolved and paused checks re-evaluated.'),
          ),
        );
        await _load();
      }
    } finally {
      await route.completed;
      noteCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Rule conflicts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              const PageIntro(
                eyebrow: 'ABSTENTION GATE',
                eyebrowTone: Tone.warning,
                title: 'Source-of-truth conflicts',
                subtitle: 'Contradictory rules or verified facts pause review rather than guessing a verdict.',
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['open', 'resolved', 'all'].map((tab) {
                    final active = _filter == tab;
                    return Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = tab),
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
                            tab.toUpperCase(),
                            style: AppTheme.monoLabel(
                              color: active ? AppTheme.tealText : AppTheme.ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const LoadingBlock(label: 'Loading conflict queue…')
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_visible.isEmpty)
                const EmptyStateCard(
                  title: 'No internal conflicts detected',
                  message: 'When active rules and verified facts disagree on the same topic, they escalate side-by-side here.',
                  icon: Icons.balance_rounded,
                )
              else
                ..._visible.map(_conflictCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conflictCard(Map<String, dynamic> conflict) {
    final status = conflict['status']?.toString() ?? 'open';
    final isOpen = status == 'open';
    final clauses = (conflict['clauses'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        radius: 18,
        borderColor: isOpen
            ? AppTheme.warning.withValues(alpha: 0.45)
            : AppTheme.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(
                  label: isOpen ? 'Paused' : 'Resolved',
                  tone: isOpen ? Tone.warning : Tone.success,
                  solid: true,
                  compact: true,
                ),
                Text(
                  'Topic: ${conflict['topic_key'] ?? 'unknown'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoLabel(color: AppTheme.ink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${conflict['brand_name'] ?? 'Acme'} · ${clauses.length} conflicting sources',
              style: AppTheme.labelLarge,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 540 && clauses.length >= 2;
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < clauses.length; i++) ...[
                        Expanded(child: _clauseBox(clauses[i])),
                        if (i != clauses.length - 1) const SizedBox(width: 8),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < clauses.length; i++) ...[
                      _clauseBox(clauses[i]),
                      if (i != clauses.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
            if (!isOpen && conflict['winning_source_id'] != null) ...[
              const SizedBox(height: 10),
              InlineNotice(
                tone: Tone.success,
                title:
                    'Pinned winner: ${conflict['winning_source_type']} ${conflict['winning_source_id']}',
                message: conflict['resolution_note']?.toString() ?? 'Resolved.',
              ),
            ],
            if (_canManage && isOpen) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _resolveDialog(conflict),
                  icon: const Icon(Icons.gavel_rounded, size: 16),
                  label: const Text('Resolve & pin active rule'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clauseBox(Map<String, dynamic> clause) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              StatusPill(
                label: clause['source_type']?.toString() ?? 'source',
                tone: Tone.info,
                compact: true,
              ),
              StatusPill(
                label: 'v${clause['version'] ?? '1.0.0'}',
                tone: Tone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            clause['title']?.toString() ?? clause['source_id']?.toString() ?? '',
            style: AppTheme.labelMedium.copyWith(color: AppTheme.ink),
          ),
          if ((clause['canonical_value']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Value: ${clause['canonical_value']}',
              style: AppTheme.monoLabel(color: AppTheme.tealText),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            clause['excerpt']?.toString() ?? '',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
          ),
        ],
      ),
    );
  }
}
