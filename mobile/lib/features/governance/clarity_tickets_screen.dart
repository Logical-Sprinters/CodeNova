import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';

class ClarityTicketsScreen extends StatefulWidget {
  const ClarityTicketsScreen({super.key});

  @override
  State<ClarityTicketsScreen> createState() => _ClarityTicketsScreenState();
}

class _ClarityTicketsScreenState extends State<ClarityTicketsScreen> {
  String _filter = 'all';
  List<Map<String, dynamic>> _tickets = [];
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
      final data = await BrandGuardApiService.getClarityTickets();
      if (!mounted) return;
      setState(() {
        _tickets = (data['items'] as List? ?? [])
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
    if (_filter == 'all') return _tickets;
    return _tickets
        .where((t) => (t['status']?.toString() ?? 'open') == _filter)
        .toList();
  }

  Tone _statusTone(String status) => switch (status) {
    'resolved' => Tone.success,
    'acknowledged' => Tone.info,
    _ => Tone.warning,
  };

  Future<void> _transition(
    Map<String, dynamic> ticket,
    String targetStatus,
  ) async {
    final noteCtrl = TextEditingController(
      text: ticket['resolution_note']?.toString() ?? '',
    );
    var busy = false;
    String? dialogErr;
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            targetStatus == 'resolved'
                ? 'Resolve clarity ticket'
                : 'Acknowledge clarity ticket',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rule ${ticket['rule_id']} (${ticket['override_count']} overrides on ${ticket['channel'] ?? 'all'}).',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Resolution / guideline follow-up note',
                    hintText: 'Document manual rule revision or owner note...',
                  ),
                ),
                if (dialogErr != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogErr!,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.danger),
                  ),
                ],
              ],
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
                        dialogErr = null;
                      });
                      try {
                        await BrandGuardApiService.updateClarityTicket(
                          ticketId: ticket['ticket_id'].toString(),
                          status: targetStatus,
                          resolutionNote: noteCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setDlg(() {
                            busy = false;
                            dialogErr = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving...' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    try {
      final confirmed = await Navigator.of(context).push(route);
      if (confirmed == true && mounted) {
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
        title: const Text('Clarity tickets'),
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
                eyebrow: 'OVERRIDE TELEMETRY',
                eyebrowTone: Tone.info,
                title: 'Clarity tickets',
                subtitle: 'Friction hotspots triggered by repeated coded reviewer overrides.',
              ),
              const SizedBox(height: 12),
              const InlineNotice(
                tone: Tone.navy,
                icon: Icons.security_rounded,
                title: 'Zero automatic rule mutation',
                message: 'Overrides never silently weaken or rewrite enforceable rules. Tickets route feedback to guideline owners for explicit review.',
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['all', 'open', 'acknowledged', 'resolved'].map((
                    tab,
                  ) {
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
                const LoadingBlock(label: 'Loading clarity tickets…')
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_visible.isEmpty)
                const EmptyStateCard(
                  title: 'No clarity tickets in this view',
                  message: 'When reviewers log repeated coded overrides against a rule, a friction ticket opens here automatically.',
                  icon: Icons.support_agent_rounded,
                )
              else
                ..._visible.map(_ticketCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> ticket) {
    final status = ticket['status']?.toString() ?? 'open';
    final tone = _statusTone(status);
    final breakdown = ticket['reason_breakdown'] is Map
        ? Map<String, dynamic>.from(ticket['reason_breakdown'] as Map)
        : <String, dynamic>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(
                  label: status,
                  tone: tone,
                  solid: true,
                  compact: true,
                ),
                Text(
                  '${ticket['rule_id']} · v${ticket['rule_version'] ?? '1.0.0'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoLabel(color: AppTheme.ink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${ticket['brand_name'] ?? 'Acme'} · ${ticket['override_count'] ?? 0} overrides (${ticket['channel'] ?? 'all'})',
              style: AppTheme.labelLarge.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Guideline owner: ${ticket['owner_id'] ?? 'u2'}',
              style: AppTheme.bodySmall,
            ),
            if (breakdown.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: breakdown.entries
                    .map(
                      (e) => StatusPill(
                        label: '${e.key}: ${e.value}',
                        tone: Tone.info,
                        compact: true,
                      ),
                    )
                    .toList(),
              ),
            ],
            if ((ticket['resolution_note']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              InlineNotice(
                tone: Tone.neutral,
                title: 'Owner note',
                message: ticket['resolution_note'].toString(),
              ),
            ],
            if (_canManage && status != 'resolved') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'open')
                    OutlinedButton.icon(
                      onPressed: () => _transition(ticket, 'acknowledged'),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Acknowledge'),
                    ),
                  FilledButton.icon(
                    onPressed: () => _transition(ticket, 'resolved'),
                    icon: const Icon(Icons.task_alt_rounded, size: 16),
                    label: const Text('Mark resolved'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
