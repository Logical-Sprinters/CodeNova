import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/appearance_controller.dart';
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
  bool _savingName = false;
  Map<String, bool> _preferences = {
    'email_updates': true,
    'review_activity': true,
    'product_news': false,
  };
  static const _preferenceLabels = {
    'email_updates': 'Account & security emails',
    'review_activity': 'Review activity updates',
    'product_news': 'Product announcements',
  };
  final appearance = AppearanceController.instance;

  @override
  void initState() {
    super.initState();
    // The name can also change from another screen or a refresh; repainting on
    // the session keeps every label in sync without a manual reload.
    session.addListener(_onSessionChanged);
    _load();
    _loadPreferences();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  static String _appearanceLabel(AppearanceMode mode) => switch (mode) {
    AppearanceMode.light => 'Light',
    AppearanceMode.dark => 'Dark',
    AppearanceMode.system => 'System',
  };

  /// Switches appearance immediately; the root app rebuilds with the new
  /// palette and the choice is persisted for the next launch.
  void _selectAppearance(AppearanceMode mode) {
    appearance.setMode(mode);
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
            child: Text('Sign out', style: TextStyle(color: AppTheme.danger)),
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
    final current = session.currentUser?.name ?? '';
    final controller = TextEditingController(text: current);
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Display name'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Full name'),
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(dialog, controller.text.trim());
                  }
                },
                validator: (value) {
                  final clean = (value ?? '').trim();
                  if (clean.length < 2) {
                    return 'Use at least two characters.';
                  }
                  return null;
                },
              ),
              Text(
                'Saved to your account, so it stays after sign-out and shows up '
                'in review headers.',
                style: AppTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialog, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog route animates out after `showDialog` resolves; disposing the
    // controller here would break that frame ("used after being disposed").
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final name = (submitted ?? '').trim();
    if (name.isEmpty || name == current) return;
    await _saveName(name);
  }

  /// Persists the name on the server, then reflects it immediately.
  Future<void> _saveName(String name) async {
    if (!mounted) return;
    setState(() => _savingName = true);
    try {
      final user = await BrandGuardApiService.updateDisplayName(name);
      if (!mounted) return;
      setState(() => _savingName = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Display name saved as "${user.name}".')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingName = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save the name: ${error.toString().replaceFirst('ApiException: ', '')}',
          ),
        ),
      );
    }
  }

  int _enabledPreferenceCount() =>
      _preferences.values.where((value) => value).length;

  Future<void> _loadPreferences() async {
    try {
      final data = await BrandGuardApiService.getPreferences();
      if (!mounted) return;
      setState(() {
        _preferences = {
          for (final key in _preferenceLabels.keys) key: data[key] != false,
        };
      });
    } catch (_) {
      // Preferences are informational here; the sheet reports its own errors.
    }
  }

  /// Opens the notification preferences sheet backed by the server.
  Future<void> _openPreferences() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NotificationPreferencesSheet(),
    );
    await _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
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
                onPressed: _savingName ? null : _editName,
                icon: _savingName
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.tealText,
                        ),
                      )
                    : const Icon(Icons.edit_outlined, size: 16),
                label: Text(_savingName ? 'Saving…' : 'Edit display name'),
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
          icon: Icons.inbox_outlined,
          title: 'Notification inbox',
          subtitle: 'In-app events recorded by the backend',
          tone: Tone.warning,
          onTap: () => _open(const NotificationsScreen()),
        ),
        const SizedBox(height: 8),
        NavigationRow(
          icon: Icons.tune_rounded,
          title: 'Notification preferences',
          subtitle:
              '${_enabledPreferenceCount()} of ${_preferenceLabels.length} enabled · saved to your account',
          tone: Tone.info,
          onTap: _openPreferences,
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
                  Icon(
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
                  StatusPill(label: appearance.label, tone: Tone.success),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                appearance.mode == AppearanceMode.system
                    ? 'Following your device setting '
                          '(${appearance.systemIsDark ? 'dark' : 'light'}).'
                    : 'Saved on this device.',
                style: AppTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final option in AppearanceMode.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Semantics(
                          button: true,
                          selected: appearance.mode == option,
                          label: '${_appearanceLabel(option)} appearance',
                          child: GestureDetector(
                            onTap: () => _selectAppearance(option),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: appearance.mode == option
                                    ? AppTheme.mint
                                    : AppTheme.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: appearance.mode == option
                                      ? AppTheme.teal
                                      : AppTheme.border,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    switch (option) {
                                      AppearanceMode.light =>
                                        Icons.light_mode_outlined,
                                      AppearanceMode.dark =>
                                        Icons.dark_mode_outlined,
                                      AppearanceMode.system =>
                                        Icons.brightness_auto_outlined,
                                    },
                                    size: 15,
                                    color: AppTheme.tealText,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      _appearanceLabel(option),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.labelMedium.copyWith(
                                        fontSize: 11.5,
                                        color: AppTheme.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
    AppTheme.watch(context);
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

/// Notification preferences backed by the server document.
///
/// Every toggle is saved immediately through `PUT /api/v1/auth/preferences`, so
/// the state survives sign-out and is identical on the next device.
class _NotificationPreferencesSheet extends StatefulWidget {
  const _NotificationPreferencesSheet();

  @override
  State<_NotificationPreferencesSheet> createState() =>
      _NotificationPreferencesSheetState();
}

class _NotificationPreferencesSheetState
    extends State<_NotificationPreferencesSheet> {
  static const _labels = {
    'email_updates': (
      'Account & security emails',
      'Sign-in, password and account notices.',
    ),
    'review_activity': (
      'Review activity updates',
      'When your submission is approved, rejected or needs changes.',
    ),
    'product_news': (
      'Product announcements',
      'Occasional notes about new BrandGuard rules and screens.',
    ),
  };

  Map<String, bool> _values = {
    'email_updates': true,
    'review_activity': true,
    'product_news': false,
  };
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getPreferences();
      if (!mounted) return;
      setState(() {
        _values = {for (final key in _labels.keys) key: data[key] != false};
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final previous = Map<String, bool>.from(_values);
    setState(() {
      _values[key] = value;
      _saving = true;
      _error = null;
    });
    try {
      final saved = await BrandGuardApiService.savePreferences(_values);
      if (!mounted) return;
      setState(() {
        _values = {for (final k in _labels.keys) k: saved[k] != false};
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _values = previous;
        _saving = false;
        _error = error.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Notification preferences',
                    style: AppTheme.titleMedium.copyWith(
                      color: AppTheme.inkStrong,
                    ),
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Saved to your account on the server — not just this device.',
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final entry in _labels.entries)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _values[entry.key] ?? false,
                  onChanged: _saving
                      ? null
                      : (value) => _toggle(entry.key, value),
                  title: Text(
                    entry.value.$1,
                    style: AppTheme.labelLarge.copyWith(color: AppTheme.ink),
                  ),
                  subtitle: Text(entry.value.$2, style: AppTheme.bodySmall),
                ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              InlineNotice(
                tone: Tone.danger,
                title: 'Could not save preferences',
                message: _error!,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
