import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/demo_auth.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../dashboard/home_dashboard_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _remember = false, _demo = false;
  bool _checkingConnection = true;
  String? _error, _notice, _connectionError, _authProvider;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _remember = prefs.getBool(DemoAuth.rememberEmailKey) ?? false;
        if (_remember && _email.text.isEmpty) {
          _email.text = prefs.getString(DemoAuth.rememberedEmailKey) ?? '';
        }
      });
    } catch (_) {
      // A preferences failure must not prevent a real server connection/login.
    }
    if (mounted) await _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _checkingConnection = true;
      _connectionError = null;
    });
    try {
      final status = await BrandGuardApiService.request(
        'GET',
        '/api/v1/auth/config',
        authenticated: false,
      );
      final provider = status['auth_provider'];
      if (provider != 'local' && provider != 'supabase') {
        throw const ApiException(
          'Could not verify the server configuration. Try again.',
        );
      }
      if (!mounted) return;
      setState(() {
        _authProvider = provider as String;
        // Fail closed: public local-demo values appear only after an explicit
        // successful local-server response, never on a timeout or cloud server.
        _demo = provider == 'local' && status['demo_accounts_enabled'] == true;
        _checkingConnection = false;
        if (!_demo && !_busy && DemoAuth.findAccount(_email.text) != null) {
          _email.clear();
          _password.clear();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _demo = false;
        _checkingConnection = false;
        _connectionError = error.toString();
      });
    }
  }

  String get _serverLabel {
    try {
      return Uri.parse(BrandGuardApiService.baseUrl).authority;
    } catch (_) {
      return 'Check API_BASE configuration';
    }
  }

  String? _emailError(String value) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _fill(DemoAccount account) {
    setState(() {
      _email.text = account.email;
      _password.text = DemoAuth.password;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _openDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(DemoAuth.rememberEmailKey, _remember);
      if (_remember) {
        await prefs.setString(DemoAuth.rememberedEmailKey, _email.text.trim());
      } else {
        await prefs.remove(DemoAuth.rememberedEmailKey);
      }
      final user = session.currentUser!;
      await prefs.setString('bg_profile_name', user.name);
      await prefs.setString('bg_profile_email', user.email ?? '');
      await prefs.setString(
        'bg_profile_role',
        user.role == 'reviewer' ? 'Reviewer' : 'Creator',
      );
    } catch (_) {
      // Preferences are not authentication storage.
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeDashboardScreen()),
    );
  }

  Future<void> _login() async {
    final invalid =
        _emailError(_email.text) ??
        (_password.text.isEmpty ? 'Enter your password.' : null);
    if (invalid != null) {
      setState(() {
        _error = invalid;
        _notice = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await BrandGuardApiService.login(_email.text, _password.text);
      if (!mounted) return;
      await _openDashboard();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _account({bool recover = false}) async {
    final name = TextEditingController();
    final email = TextEditingController(text: _email.text);
    final password = TextEditingController();
    String? error;
    bool busy = false, confirmationRequired = false;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(recover ? 'Reset password' : 'Create account'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!recover)
                    TextField(
                      controller: name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  if (!recover)
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (at least 8 characters)',
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final invalid =
                          _emailError(email.text) ??
                          (!recover && name.text.trim().length < 2
                              ? 'Enter your name (at least 2 characters).'
                              : null) ??
                          (!recover &&
                                  (password.text.length < 8 ||
                                      password.text.length > 128)
                              ? 'Use a password with 8 to 128 characters.'
                              : null);
                      if (invalid != null) {
                        update(() => error = invalid);
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        if (recover) {
                          await BrandGuardApiService.recover(email.text);
                        } else {
                          final data = await BrandGuardApiService.signup(
                            name.text,
                            email.text,
                            password.text,
                          );
                          confirmationRequired =
                              data['requires_confirmation'] == true;
                        }
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } catch (e) {
                        if (!dialog.mounted) return;
                        update(() {
                          error = e.toString();
                          busy = false;
                        });
                      }
                    },
              child: Text(
                busy
                    ? 'Please wait...'
                    : recover
                    ? 'Send instructions'
                    : 'Create account',
              ),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    final submittedEmail = email.text.trim();
    name.dispose();
    email.dispose();
    password.dispose();
    if (!mounted || result != true) return;
    if (recover || confirmationRequired) {
      setState(() {
        _error = null;
        _email.text = submittedEmail;
        _password.clear();
        _notice = recover
            ? 'If this account exists, check your inbox or spam folder for password reset instructions.'
            : 'Account created. Check your inbox or spam folder, confirm your email, then sign in.';
      });
    } else {
      _email.text = submittedEmail;
      await _openDashboard();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F8F5),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  size: 54,
                  color: Color(0xFF22A895),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('Sign in with your BrandGuard email and password.'),
                const SizedBox(height: 8),
                Text(
                  'Server: $_serverLabel',
                  key: const ValueKey('server-address'),
                  style: const TextStyle(fontSize: 12),
                ),
                if (_checkingConnection)
                  const Text(
                    'Checking server connection...',
                    style: TextStyle(fontSize: 12),
                  )
                else if (_connectionError != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connectionError!,
                        key: const ValueKey('server-connection-error'),
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                      TextButton(
                        key: const ValueKey('retry-connection'),
                        onPressed: _checkConnection,
                        child: const Text('Retry connection'),
                      ),
                    ],
                  )
                else
                  Text(
                    _authProvider == 'local'
                        ? 'Connected to local server'
                        : 'Connected to live service',
                    key: const ValueKey('server-connected'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF006B5E),
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('demo-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('demo-password'),
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) {
                    if (!_busy) _login();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  key: const ValueKey('demo-remember-email'),
                  value: _remember,
                  onChanged: (value) =>
                      setState(() => _remember = value ?? false),
                  title: const Text('Remember email only'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      key: const ValueKey('demo-login-error'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _notice!,
                      key: const ValueKey('auth-notice'),
                      style: const TextStyle(color: Color(0xFF006B5E)),
                    ),
                  ),
                FilledButton(
                  key: const ValueKey('demo-sign-in'),
                  onPressed: _busy ? null : _login,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_busy ? 'Signing in...' : 'Sign In'),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _account(),
                      child: const Text('Create account'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _account(recover: true),
                      child: const Text('Forgot password?'),
                    ),
                  ],
                ),
                if (_demo)
                  Container(
                    key: const ValueKey('demo-access-card'),
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Local demonstration accounts',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'creator@brandguard.demo\nreviewer@brandguard.demo',
                        ),
                        const Text('Password for both: Demo@12345'),
                        Wrap(
                          spacing: 10,
                          children: [
                            TextButton(
                              key: const ValueKey('demo-creator'),
                              onPressed: () => _fill(DemoAuth.creator),
                              child: const Text('Use Creator'),
                            ),
                            TextButton(
                              key: const ValueKey('demo-reviewer'),
                              onPressed: () => _fill(DemoAuth.reviewer),
                              child: const Text('Use Reviewer'),
                            ),
                          ],
                        ),
                        const Text(
                          'Local server only. These public demo accounts are not live cloud accounts.',
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Tokens stay in memory; the app does not save your password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
