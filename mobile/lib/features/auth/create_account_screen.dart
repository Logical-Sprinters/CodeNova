import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';

/// Account creation. Organisation name is captured for context only: the
/// backend contract accepts name/email/password, and roles can never be
/// self-assigned from this screen.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final _name = TextEditingController();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _org = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agreed = false, _busy = false, _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _org.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _emailError(String value) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  int get _strength {
    final value = _password.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'''[^A-Za-z0-9]''').hasMatch(value)) score++;
    return score.clamp(0, 4);
  }

  String get _strengthLabel => switch (_strength) {
    0 => 'Too short',
    1 => 'Weak',
    2 => 'Fair',
    3 => 'Strong',
    _ => 'Very strong',
  };

  Future<void> _submit() async {
    final invalid =
        _emailError(_email.text) ??
        (_name.text.trim().length < 2
            ? 'Enter your full name (at least 2 characters).'
            : null) ??
        (_password.text.length < 8 || _password.text.length > 128
            ? 'Use a password with 8 to 128 characters.'
            : null) ??
        (_password.text != _confirm.text ? 'Passwords do not match.' : null) ??
        (!_agreed ? 'Please accept the terms to continue.' : null);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await BrandGuardApiService.signup(
        _name.text,
        _email.text,
        _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context, _email.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['requires_confirmation'] == true
                ? 'Account created. Confirm your email, then sign in.'
                : 'Account created. Sign in to continue.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Create your account'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: BrandMark(size: 34, radius: 10),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            Center(
              child: Column(
                children: [
                  const BrandMark(size: 58, radius: 17),
                  const SizedBox(height: 12),
                  Text('Create your account', style: AppTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Get started with BrandGuard governance.',
                    style: AppTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const InlineNotice(
              tone: Tone.info,
              title: 'Default creator access',
              message: 'Administrative and Authorised Reviewer roles are granted only through organisation approval. This form cannot choose a role.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('create-account-name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('create-account-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Work email',
                hintText: 'name@company.com',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                helperText: 'Used only for sign-in and account recovery.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _org,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Organisation name (optional)',
                prefixIcon: Icon(Icons.apartment_rounded),
                helperText: 'Not stored as a tenant: this server has no organisation model.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('create-account-password'),
              controller: _password,
              obscureText: _obscure,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'STRENGTH: ${_strengthLabel.toUpperCase()}',
                  style: AppTheme.monoLabel(
                    color: _strength >= 3 ? AppTheme.success : AppTheme.muted,
                  ),
                ),
                const Spacer(),
                Text('$_strength of 4', style: AppTheme.monoLabel()),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < _strength
                            ? (_strength >= 3
                                  ? AppTheme.success
                                  : AppTheme.warning)
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  if (i != 3) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Use 8+ characters with an uppercase letter, a number and a symbol.',
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('create-account-confirm'),
              controller: _confirm,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon:
                    _confirm.text.isNotEmpty && _confirm.text == _password.text
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.success,
                        size: 20,
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _agreed = !_agreed),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _agreed,
                      onChanged: (value) =>
                          setState(() => _agreed = value ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'I understand checks assist review; they are not legal clearance, and synthetic approvals are not publication sign-off.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              InlineNotice(
                tone: Tone.danger,
                title: 'Could not create the account',
                message: _error!,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const ValueKey('create-account'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Create Account'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Already have an account?',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                ),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
