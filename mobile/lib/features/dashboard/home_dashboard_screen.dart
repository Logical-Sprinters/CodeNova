import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../checks/new_brand_check_screen.dart';
import '../chat/chat_assistant_screen.dart';
import '../guidelines/fact_sources_screen.dart';
import '../guidelines/upload_rule_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reviews/review_queue_screen.dart';
import '../workspace/workspace_hub_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key, this.embedded = false});

  /// When true the screen is hosted inside [BrandGuardShell] and only renders
  /// its scrolling content.
  final bool embedded;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  Map<String, dynamic>? _analytics, _system;
  List<Map<String, dynamic>> _activity = const [];
  int _unread = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // One retry: hosted Supabase can be slow on a cold start. A transient
    // failure must never leave the dashboard stuck on a loading placeholder.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final data = await Future.wait([
          BrandGuardApiService.getJson('/api/v1/analytics'),
          BrandGuardApiService.getJson('/api/v1/notifications'),
          BrandGuardApiService.getJson('/api/v1/system/status'),
        ]);
        if (!mounted) return;
        setState(() {
          _analytics = data[0];
          _unread = (data[1]['unread'] as num?)?.toInt() ?? 0;
          _activity = (data[1]['items'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .take(3)
              .toList();
          _system = data[2];
          _loading = false;
          _error = null;
        });
        return;
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _error = lastError?.toString() ?? 'The server did not respond.';
      _loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted && session.accessToken != null) await _load();
  }

  int _metric(String key) => (_analytics?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final content = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _hero(),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingBlock(label: 'Loading live governance data…')
          else if (_error != null)
            ErrorBlock(message: _error!, onRetry: _load)
          else ...[
            Row(
              children: [
                Text(
                  'LIVE OVERVIEW',
                  style: AppTheme.monoLabel(color: AppTheme.tealText),
                ),
                const Spacer(),
                Text(
                  'Pull to refresh',
                  style: AppTheme.monoLabel().copyWith(fontSize: 9),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _metrics(),
            const SizedBox(height: 8),
            Text(
              session.currentUser?.isReviewer == true
                  ? 'Reviewer scope: every accessible submission.'
                  : 'Creator scope: only your own submissions.',
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const SectionHeading(
              title: 'Fast actions',
              caption: 'Everything runs against the live API',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _quickAction(
                    Icons.fact_check_rounded,
                    'Review queue',
                    '${_metric('pending')} pending',
                    () => _open(const ReviewQueueScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(
                    Icons.rule_rounded,
                    'Upload rule',
                    'Versioned checks',
                    () => _open(const UploadRuleScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(
                    Icons.fact_check_outlined,
                    'Fact sources',
                    'Verified evidence',
                    () => _open(const FactSourcesScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionHeading(
              title: 'Recent activity',
              caption: _activity.isEmpty ? null : 'From your notifications',
              trailing: TextButton(
                onPressed: () => _open(const NotificationsScreen()),
                child: Text('View all${_unread > 0 ? " ($_unread)" : ""}'),
              ),
            ),
            const SizedBox(height: 8),
            if (_activity.isEmpty)
              const EmptyStateCard(
                title: 'No activity yet',
                message: 'Run a brand check or wait for a reviewer decision — events appear here as soon as the server records them.',
                icon: Icons.notifications_none_rounded,
              )
            else
              ..._activity.map(_activityRow),
            const SizedBox(height: 18),
            _systemStrip(),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => _open(const WorkspaceHubScreen()),
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: const Text('Open full workspace, ledger & receipts'),
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellHeader(
            title: 'BrandGuard',
            subtitle: 'Home · governance active',
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () => _open(const NotificationsScreen()),
                icon: Badge(
                  isLabelVisible: _unread > 0,
                  backgroundColor: AppTheme.danger,
                  label: Text(
                    '$_unread',
                    style: AppTheme.monoLabel(color: Colors.white),
                  ),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ],
          ),
          Expanded(child: content),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(child: content),
    );
  }

  Widget _hero() {
    final user = session.currentUser;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A4B), AppTheme.navyDeep],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.raisedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.mintBright.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppTheme.mintBright,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'GOVERNANCE ACTIVE',
                      style: AppTheme.monoLabel(color: AppTheme.mintBright),
                    ),
                  ],
                ),
              ),
              RoleChip(isReviewer: user?.isReviewer == true, onDark: true),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$greeting, ${_firstName(user?.name)}',
            style: AppTheme.headlineMedium.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'No finding without evidence. No approval without a version.',
            style: AppTheme.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _open(const NewBrandCheckScreen()),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.teal,
                minimumSize: const Size(0, 46),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Brand Check'),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _open(const ChatAssistantScreen()),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                foregroundColor: AppTheme.mintBright,
                side: BorderSide(
                  color: AppTheme.mintBright.withValues(alpha: 0.35),
                ),
                minimumSize: const Size(0, 44),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Ask BrandGuard Assistant'),
            ),
          ),
        ],
      ),
    );
  }

  String _firstName(String? name) {
    final clean = (name ?? 'there').trim();
    if (clean.isEmpty) return 'there';
    return clean.split(RegExp(r'\s+')).first;
  }

  Widget _metrics() {
    final total = _metric('total_checks');
    final pending = _metric('pending');
    final approved = _metric('approved');
    final rejected = _metric('rejected');
    final findings = _metric('total_findings');
    final decided = approved + rejected;
    final cards = <Widget>[
      MetricCard(
        label: 'Submissions',
        value: '$total',
        tone: Tone.navy,
        icon: Icons.folder_copy_outlined,
        footnote: 'Total checks on record',
      ),
      MetricCard(
        label: 'Pending',
        value: '$pending',
        tone: pending > 0 ? Tone.warning : Tone.success,
        icon: Icons.schedule_rounded,
        footnote: 'Awaiting review',
      ),
      MetricCard(
        label: 'Approved',
        value: '$approved',
        tone: Tone.success,
        icon: Icons.verified_rounded,
        footnote: decided > 0
            ? '${(approved * 100 / decided).round()}% of decisions'
            : 'No decisions yet',
      ),
      MetricCard(
        label: 'Findings',
        value: '$findings',
        tone: findings > 0 ? Tone.danger : Tone.success,
        icon: Icons.report_gmailerrorred_rounded,
        footnote: 'Detections & flags logged',
      ),
    ];
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final columns = constraints.maxWidth >= 520 ? 4 : 2;
            final cardWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  SizedBox(width: cardWidth, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          radius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'DECISION MIX',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.monoLabel(color: AppTheme.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      '${_metric('scan_passed')} clean scans',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ProgressLine(
                value: total == 0 ? 0 : approved / total,
                caption: total == 0
                    ? 'No checks recorded yet.'
                    : '$approved approved · $pending pending · $rejected rejected of $total total',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickAction(
    IconData icon,
    String title,
    String caption,
    VoidCallback onTap,
  ) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      radius: 16,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.mint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: AppTheme.tealText),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.labelMedium.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.monoLabel().copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(Map<String, dynamic> item) {
    final unread = item['read'] != true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        radius: 16,
        onTap: () => _open(const NotificationsScreen()),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: unread ? AppTheme.infoBg : AppTheme.neutralBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                unread
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 17,
                color: unread ? AppTheme.info : AppTheme.muted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title']?.toString() ?? 'Activity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelLarge.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item['body']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stamp(item['created_at']),
                    style: AppTheme.monoLabel().copyWith(fontSize: 9),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 4, left: 4),
                decoration: BoxDecoration(
                  color: AppTheme.info,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _stamp(Object? value) {
    final text = value?.toString() ?? '';
    if (text.length >= 16) {
      return text.substring(0, 16).replaceFirst('T', ' · ');
    }
    return text;
  }

  Widget _systemStrip() {
    final aiConfigured = _system?['ai_configured'] == true;
    final database = _system?['database'] ?? '—';
    final provider = _system?['auth_provider'] ?? '—';
    return InlineNotice(
      tone: aiConfigured ? Tone.success : Tone.warning,
      icon: aiConfigured ? Icons.auto_awesome_rounded : Icons.info_outline,
      title: aiConfigured
          ? 'AI comparison enabled'
          : 'AI not configured: checks abstain on factual claims',
      message:
          'Backend: $database · auth: $provider. Deterministic rules and human review still run. A clean scan is not publication approval.',
    );
  }
}
