import 'package:material_ui/material_ui.dart';

import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../auth/sign_in_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _status;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson('/api/v1/system/status');
      if (mounted) setState(() => _status = data);
    } catch (_) {}
  }

  Future<void> _logout() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
          'Your in-memory tokens will be cleared and the server session will be revoked when reachable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Sign Out'),
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

  @override
  Widget build(BuildContext context) {
    final user = session.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(
            radius: 38,
            child: Icon(Icons.person_outline, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            user?.name ?? 'Not signed in',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(user?.email ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Role: ${user?.role ?? "none"}', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const Text(
            'Roles are assigned by the server. They cannot be changed by editing local preferences.',
          ),
          const SizedBox(height: 24),
          if (_status != null)
            ..._status!.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${entry.key}: ${entry.value}'),
              ),
            ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            key: const ValueKey('demo-sign-out'),
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
