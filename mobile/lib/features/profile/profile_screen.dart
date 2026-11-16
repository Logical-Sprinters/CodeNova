import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../app/ui/brandguard_shell.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../auth/sign_in_screen.dart';
import '../notifications/notifications_screen.dart';
import '../workspace/server_records_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _status;
  String _theme = 'Light';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson('/api/v1/system/status');
      if (mounted) setState(() => _status = data);
    } catch (_) {
      // Status is informational; the profile stays usable offline.
    }
  }

  Future<void> _logout() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign out of BrandGuard?'),
        content: const Text(
          'Your in-memory tokens are cleared and the server session is revoked when reachable. Passwords are never stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await BrandGuardApiService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: session.currentUser?.name ?? '',
    );
    final updated = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Display name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            Text(
              'The backend keeps the authoritative name. This changes your local display only for this session.',
              style: AppTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = updated?.trim() ?? '';
    final user = session.currentUser;
    if (name.length < 2 || user == null) return;
    session.updateUser(
      User(userId: user.userId, name: name, role: user.role, email: user.email),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Display name updated for this session.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = session.currentUser;
    final isReviewer = user?.isReviewer == true;
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InitialsAvatar(name: user?.name ?? 'BrandGuard', radius: 36),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.teal,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                user?.name ?? 'Not signed in',
                style: AppTheme.headlineSmall.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                user?.email ?? 'No email on this session',
                style: AppTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  StatusPill(
                    label: isReviewer ? 'Authorised Reviewer' : 'Creator',
                    tone: isReviewer ? Tone.success : Tone.info,
                    icon: isReviewer
                        ? Icons.verified_rounded
                        : Icons.edit_note_rounded,
                  ),
                  StatusPill(label: 'Active session', tone: Tone.neutral),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _editName,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit display name'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InlineNotice(
          tone: Tone.navy,
          icon: Icons.lock_outline_rounded,
          title: 'Role governance safe-lock',
          message: 'Roles come from the server (Supabase app_metadata or the local user store). Elevation is not possible from this device.',
        ),
        const SizedBox(height: 18),
        const SectionHeading(title: 'Account & security'),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.person_outline_rounded,
          title: 'My profile',
          subtitle: 'Display name and session identity',
          onTap: _editName,
        ),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.password_rounded,
          title: 'Password & sessions',
          subtitle: 'Tokens live in memory; sign in again to rotate them.',
          tone: Tone.info,
          onTap: () => _open(const _SessionInfoSheet()),
        ),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.notifications_none_rounded,
          title: 'Notification preferences',
          subtitle: 'In-app events recorded by the backend',
          tone: Tone.warning,
          onTap: () => _open(const NotificationsScreen()),
        ),
        const SizedBox(height: 18),
        const SectionHeading(title: 'Preferences & appearance'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.palette_outlined,
                    size: 18,
                    color: AppTheme.tealText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Appearance',
                      style: AppTheme.labelLarge.copyWith(fontSize: 13),
                    ),
                  ),
                  StatusPill(label: 'Light', tone: Tone.success),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final option in ['Light', 'Dark', 'System'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            if (option == 'Light') {
                              setState(() => _theme = option);
                              return;
                            }
                            setState(() => _theme = option);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$option appearance is not shipped yet — the audited light theme stays active.',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _theme == option
                                  ? AppTheme.mint
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _theme == option
                                    ? AppTheme.teal
                                    : AppTheme.border,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  option == 'Light'
                                      ? Icons.light_mode_outlined
                                      : option == 'Dark'
                                      ? Icons.dark_mode_outlined
                                      : Icons.brightness_auto_outlined,
                                  size: 15,
                                  color: AppTheme.tealText,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  option,
                                  style: AppTheme.labelMedium.copyWith(
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeading(title: 'Governance & evidence'),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.receipt_long_outlined,
          title: 'My processing receipts',
          subtitle: 'Protected records for accessible submissions',
          tone: Tone.navy,
          onTap: () => _open(
            const ServerRecordsScreen(
              kind: 'receipts',
              title: 'Processing Receipts',
            ),
          ),
        ),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.policy_outlined,
          title: 'Audit ledger',
          subtitle: 'Governance events recorded by the server',
          tone: Tone.success,
          onTap: () => _open(
            const ServerRecordsScreen(kind: 'audit', title: 'Audit Ledger'),
          ),
        ),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.history_rounded,
          title: 'Version history',
          subtitle: 'Stored versions of checks you can access',
          tone: Tone.info,
          onTap: () => _open(
            const ServerRecordsScreen(
              kind: 'history',
              title: 'Version History',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONNECTED BACKEND',
                style: AppTheme.monoLabel(color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              DetailRow(
                label: 'Auth provider',
                value: '${_status?['auth_provider'] ?? '—'}',
              ),
              DetailRow(
                label: 'Database',
                value: '${_status?['database'] ?? '—'}',
              ),
              DetailRow(
                label: 'AI comparison',
                value: _status?['ai_configured'] == true
                    ? 'Configured'
                    : 'Disabled · abstains',
                valueColor: _status?['ai_configured'] == true
                    ? AppTheme.success
                    : AppTheme.warning,
              ),
              DetailRow(label: 'App version', value: '2.1.0 (build 4)'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const ValueKey('demo-sign-out'),
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.35)),
              backgroundColor: AppTheme.dangerBg,
            ),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Log out of BrandGuard'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'BrandGuard · pre-publication governance\nNo finding without evidence. No approval without a version.',
            textAlign: TextAlign.center,
            style: AppTheme.monoLabel().copyWith(fontSize: 9.5),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          const ShellHeader(title: 'Profile', subtitle: 'Account & governance'),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Profile & settings')),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _SessionInfoSheet extends StatelessWidget {
  const _SessionInfoSheet();

  @override
  Widget build(BuildContext context) {
    final user = session.currentUser;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Password & sessions')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current session', style: AppTheme.titleMedium),
                const SizedBox(height: 10),
                DetailRow(label: 'User id', value: user?.userId ?? '—'),
                DetailRow(label: 'Role', value: user?.role ?? '—'),
                DetailRow(
                  label: 'Access token',
                  value: session.accessToken == null
                      ? 'Not present'
                      : 'Held in memory only',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const InlineNotice(
            tone: Tone.info,
            title: 'How to change your password',
            message: 'Supabase-hosted accounts: use “Reset access?” on the sign-in screen. Local server accounts: the API requires your current password, so ask an administrator.',
          ),
        ],
      ),
    );
  }
}
