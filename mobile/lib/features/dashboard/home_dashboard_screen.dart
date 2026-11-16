import 'package:material_ui/material_ui.dart';

import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../checks/new_brand_check_screen.dart';
import '../reviews/review_queue_screen.dart';
import '../guidelines/brand_guidelines_screen.dart';
import '../guidelines/upload_rule_screen.dart';
import '../guidelines/fact_sources_screen.dart';
import '../drafts/drafts_screen.dart';
import '../workspace/workspace_hub_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../analytics/analytics_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});
  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  Map<String, dynamic>? _analytics, _system;
  int _unread = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Future.wait([
        BrandGuardApiService.getJson('/api/v1/analytics'),
        BrandGuardApiService.getJson('/api/v1/notifications'),
        BrandGuardApiService.getJson('/api/v1/system/status'),
      ]);
      if (!mounted) return;
      setState(() {
        _analytics = data[0];
        _unread = data[1]['unread'] as int? ?? 0;
        _system = data[2];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted && session.accessToken != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF142C3B), teal = Color(0xFF006B5E);
    final user = session.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text(
          'BrandGuard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () => _open(const NotificationsScreen()),
            tooltip: 'Notifications ($_unread unread)',
            icon: Badge(
              label: Text('$_unread'),
              isLabelVisible: _unread > 0,
              child: const Icon(Icons.notifications_none),
            ),
          ),
          IconButton(
            onPressed: () => _open(const ProfileScreen()),
            tooltip: 'My profile',
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF81F7E1),
                    size: 34,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Welcome, ${user?.name ?? "User"}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.isReviewer == true
                        ? 'Review exact content. Manage shared brand evidence.'
                        : 'Create with confidence. Track every check and decision.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Server role: ${user?.role ?? "none"}',
                    style: const TextStyle(color: Color(0xFF81F7E1)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _open(const NewBrandCheckScreen()),
              icon: const Icon(Icons.add),
              label: const Padding(
                padding: EdgeInsets.all(13),
                child: Text('New Brand Check'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'LIVE OVERVIEW',
                    style: TextStyle(
                      fontSize: 11,
                      color: teal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  tooltip: 'Refresh overview',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Could not load server data: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_analytics != null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric('Total checks', _analytics!['total_checks']),
                  _metric('Pending', _analytics!['pending']),
                  _metric('Approved', _analytics!['approved']),
                  _metric('Rejected', _analytics!['rejected']),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                user?.isReviewer == true
                    ? 'Reviewer scope: all accessible submissions.'
                    : 'Creator scope: only your submissions.',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'YOUR WORKSPACE',
              style: TextStyle(
                fontSize: 11,
                color: teal,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _action(
              'Saved Drafts',
              'Private, versioned drafts stored on the server',
              Icons.edit_note,
              () => _open(const DraftsScreen()),
            ),
            _action(
              'Review Queue',
              'Checks, exact text, findings and human decisions',
              Icons.assignment_turned_in_outlined,
              () => _open(const ReviewQueueScreen()),
            ),
            _action(
              'Brand Guidelines',
              'Shared guidance for your brand',
              Icons.menu_book_outlined,
              () => _open(const BrandGuidelinesScreen()),
            ),
            _action(
              'Enforceable Rules',
              'Current, versioned backend checks',
              Icons.rule,
              () => _open(const UploadRuleScreen()),
            ),
            _action(
              'Fact Sources',
              'Reviewer-approved evidence and document ingestion',
              Icons.fact_check_outlined,
              () => _open(const FactSourcesScreen()),
            ),
            _action(
              'Analytics & Reports',
              'Live metrics and a copyable report',
              Icons.analytics_outlined,
              () => _open(const AnalyticsScreen()),
            ),
            _action(
              'Workspace',
              'Version history, audit ledger and receipts',
              Icons.layers_outlined,
              () => _open(const WorkspaceHubScreen()),
            ),
            const SizedBox(height: 20),
            if (_system != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected backend: ${_system!['database']} / ${_system!['auth_provider']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _system!['ai_configured'] == true
                          ? 'AI configured. Each check still requires suitable verified sources and a successful provider response.'
                          : 'AI not configured: checks explicitly abstain instead of pretending to verify factual claims.',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Scan results are not publication approval. An independent reviewer makes the final decision.',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, dynamic value) => SizedBox(
    width: 153,
    child: Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5EAE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${value ?? 0}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF142C3B),
            ),
          ),
          const SizedBox(height: 3),
          Text(label),
        ],
      ),
    ),
  );
  Widget _action(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFF006B5E)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );
}
