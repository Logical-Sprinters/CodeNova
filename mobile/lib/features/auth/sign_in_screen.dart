import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/demo_auth.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../../app/ui/brandguard_shell.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _remember = true, _obscure = true;
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
        _remember =
            prefs.getBool(BrandGuardApiService.rememberMePrefKey) ??
            prefs.getBool(DemoAuth.rememberEmailKey) ??
            true;
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
      final isLocalDemo =
          provider == 'local' && status['demo_accounts_enabled'] == true;
      setState(() {
        _authProvider = provider as String;
        _checkingConnection = false;
        if (!isLocalDemo &&
            !_busy &&
            DemoAuth.findAccount(_email.text) != null) {
          _email.clear();
          _password.clear();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
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

  Future<void> _openDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(BrandGuardApiService.rememberMePrefKey, _remember);
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
      MaterialPageRoute(builder: (_) => const BrandGuardShell()),
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
      await BrandGuardApiService.login(
        _email.text,
        _password.text,
        rememberMe: _remember,
      );
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

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: BrandMark(
                          size: 42,
                          radius: 13,
                          showWordmark: true,
                          subtitle: 'GOVERNANCE VAULT',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.mint,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.teal.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'v2.4',
                          style: AppTheme.monoLabel(color: AppTheme.tealText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text('Welcome back', style: AppTheme.headlineLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to protect and audit your brand assets.',
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 18),
                  SurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.domain_verification_outlined,
                              size: 18,
                              color: AppTheme.tealText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Email & password sign-in',
                                style: AppTheme.labelLarge,
                              ),
                            ),
                            EntityChip(
                              provider: _checkingConnection
                                  ? null
                                  : _authProvider,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _connectionState(),
                        const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey('demo-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            hintText: 'name@company.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('demo-password'),
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) {
                            if (!_busy) _login();
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                key: const ValueKey('demo-remember-email'),
                                value: _remember,
                                onChanged: (value) =>
                                    setState(() => _remember = value ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _remember = !_remember),
                                child: Text(
                                  'Remember me (stay signed in)',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.ink,
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _openRecover,
                              child: const Text('Reset access?'),
                            ),
                          ],
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              key: const ValueKey('demo-login-error'),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.dangerBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.danger.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 16,
                                    color: AppTheme.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: AppTheme.bodySmall.copyWith(
                                        color: AppTheme.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _notice!,
                              key: const ValueKey('auth-notice'),
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.tealText,
                              ),
                            ),
                          ),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            key: const ValueKey('demo-sign-in'),
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Sign In to Dashboard'),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Passwords are never saved on this device. Uncheck "Remember me" on shared devices.',
                                textAlign: TextAlign.center,
                                style: AppTheme.monoLabel().copyWith(
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'New organisation?',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _openSignup,
                        child: const Text('Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _connectionState() {
    if (_checkingConnection) {
      // Deliberately static: an indefinite spinner here would keep the page
      // animating while a slow health check runs, which is wasteful and makes
      // automated layout tests wait for a frame that never settles.
      return Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 14, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Checking server connection…',
              style: AppTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    if (_connectionError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _connectionError!,
            key: const ValueKey('server-connection-error'),
            style: AppTheme.bodySmall.copyWith(color: AppTheme.danger),
          ),
          TextButton.icon(
            key: const ValueKey('retry-connection'),
            onPressed: _checkConnection,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry connection'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppTheme.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _authProvider == 'local'
                ? 'Connected to local server'
                : 'Connected to live service',
            key: const ValueKey('server-connected'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.tealText),
          ),
        ),
        Flexible(
          child: Text(
            'Server: $_serverLabel',
            key: const ValueKey('server-address'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTheme.monoLabel().copyWith(fontSize: 9),
          ),
        ),
      ],
    );
  }

  Future<void> _openSignup() async {
    final createdEmail = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(initialEmail: _email.text),
      ),
    );
    if (!mounted || createdEmail == null) return;
    setState(() {
      _email.text = createdEmail;
      _notice = 'Account created. Confirm your email if required, then sign in. Roles are assigned by an administrator.';
      _error = null;
    });
  }

  Future<void> _openRecover() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: _email.text),
      ),
    );
    if (!mounted || sent != true) return;
    setState(() {
      _notice = 'If this account exists, check your inbox or spam folder for reset instructions.';
      _error = null;
    });
  }
}

/// Shows which authentication provider answered; never invents SSO support.
class EntityChip extends StatelessWidget {
  const EntityChip({super.key, required this.provider});

  final String? provider;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final text = provider == null
        ? 'CHECKING'
        : provider == 'supabase'
        ? 'LIVE AUTH'
        : 'LOCAL AUTH';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: AppTheme.monoLabel(color: AppTheme.navy)),
    );
  }
}
