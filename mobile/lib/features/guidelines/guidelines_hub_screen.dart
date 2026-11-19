import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import 'brand_guidelines_screen.dart';
import 'fact_sources_screen.dart';
import 'upload_rule_screen.dart';
import 'conflict_manager_screen.dart';

/// Guidelines tab: shared guidance, enforceable rules and verified fact
/// sources, summarised from the live API.
class GuidelinesHubScreen extends StatefulWidget {
  const GuidelinesHubScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<GuidelinesHubScreen> createState() => _GuidelinesHubScreenState();
}

class _GuidelinesHubScreenState extends State<GuidelinesHubScreen> {
  Map<String, dynamic>? _guidelines, _rules, _facts;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // The library endpoints are brand-scoped query endpoints; calling the
        // bare paths returns 404, so the brand is always supplied explicitly.
        const query = '?brand_name=Acme';
        final results = await Future.wait([
          BrandGuardApiService.getJson('/api/v1/library/guidelines$query'),
          BrandGuardApiService.getJson('/api/v1/library/rules$query'),
          BrandGuardApiService.getJson('/api/v1/library/facts$query'),
        ]);
        if (!mounted) return;
        setState(() {
          _guidelines = results[0];
          _rules = results[1];
          _facts = results[2];
          _error = null;
          _loading = false;
        });
        return;
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _error = lastError?.toString() ?? 'The server did not respond.';
      _loading = false;
    });
  }

  static int _count(Map<String, dynamic>? data) {
    for (final key in ['total', 'count']) {
      final value = data?[key];
      if (value is num) return value.toInt();
    }
    for (final key in ['items', 'guidelines', 'rules', 'facts', 'sources']) {
      final value = data?[key];
      if (value is List) return value.length;
    }
    return 0;
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final isReviewer = session.currentUser?.isReviewer == true;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          PageIntro(
            eyebrow: 'AUDIT CLEARANCE',
            eyebrowTone: Tone.success,
            title: 'Brand Guidelines',
            subtitle: 'Shared guidance, enforceable rules and verified sources behind every check.',
            trailing: isReviewer
                ? IconButton(
                    tooltip: 'Manage rules',
                    onPressed: () => _open(const UploadRuleScreen()),
                    icon: const Icon(Icons.tune_rounded),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingBlock(label: 'Loading governance library…')
          else if (_error != null)
            ErrorBlock(message: _error!, onRetry: _load)
          else ...[
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Guidelines',
                    value: '${_count(_guidelines)}',
                    tone: Tone.navy,
                    icon: Icons.menu_book_rounded,
                    footnote: 'Shared documentation',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Rules',
                    value: '${_count(_rules)}',
                    tone: Tone.success,
                    icon: Icons.rule_rounded,
                    footnote: 'Versioned checks',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Sources',
                    value: '${_count(_facts)}',
                    tone: Tone.info,
                    icon: Icons.fact_check_rounded,
                    footnote: 'Evidence records',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionHeading(
              title: 'Library modules',
              caption: 'Each module writes to the live backend',
            ),
            const SizedBox(height: 8),
            NavigationRow(
              icon: Icons.menu_book_outlined,
              title: 'Brand Guidelines',
              subtitle: isReviewer
                  ? 'Add, edit or archive guidance entries.'
                  : 'Read-only: guidance is managed by reviewers.',
              tone: Tone.navy,
              onTap: () => _open(const BrandGuidelinesScreen()),
            ),
            const SizedBox(height: 8),
            NavigationRow(
              icon: Icons.rule_rounded,
              title: 'Enforceable Rules',
              subtitle: 'Rule versions, patterns and severities used by /brand/check.',
              tone: Tone.success,
              onTap: () => _open(const UploadRuleScreen()),
            ),
            const SizedBox(height: 8),
            NavigationRow(
              icon: Icons.fact_check_outlined,
              title: 'Fact Sources',
              subtitle:
                  'Upload private documents and verify eligible evidence.',
              tone: Tone.info,
              onTap: () => _open(const FactSourcesScreen()),
            ),
            const SizedBox(height: 8),
            NavigationRow(
              icon: Icons.gavel_rounded,
              title: 'Rule Conflict Manager',
              subtitle: isReviewer
                  ? 'Resolve conflicting source facts and resume affected reviews.'
                  : 'View source conflict escalation status.',
              tone: Tone.warning,
              onTap: () => _open(const ConflictManagerScreen()),
            ),
            const SizedBox(height: 16),
            InlineNotice(
              tone: Tone.warning,
              title: 'Evidence must be reviewer-approved',
              message: isReviewer
                  ? 'Only reviewer-verified sources are eligible as citations. Deterministic rules run regardless.'
                  : 'Only reviewer-verified sources are eligible as citations, so a clean scan is never a factual guarantee.',
            ),
          ],
        ],
      ),
    );

    if (widget.embedded) {
      return Column(
        children: [
          const ShellHeader(
            title: 'Guidelines',
            subtitle: 'Library · rules · evidence',
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(child: body),
    );
  }
}
