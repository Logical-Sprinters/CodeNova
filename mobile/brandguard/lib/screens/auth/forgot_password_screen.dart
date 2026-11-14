import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sign_in_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  Timer? _resendTimer;
  int _secondsRemaining = 0;
  bool _showSuccess = false;
  bool _isSending = false;

  static const Color _navy = Color(0xFF001725);
  static const Color _teal = Color(0xFF006B5E);
  static const Color _mint = Color(0xFF81F7E1);
  static const Color _background = Color(0xFFF4FAFF);
  static const Color _surfaceBlue = Color(0xFFE8F6FF);
  static const Color _outline = Color(0xFF73787C);
  static const Color _text = Color(0xFF0C1E26);
  static const Color _secondaryText = Color(0xFF43474C);

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = _text,
    double height = 1.4,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _backToSignIn() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  String _maskedEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return email;
    final name = parts.first;
    final visible = name.length == 1 ? name : name.substring(0, 1);
    return '$visible***@${parts[1]}';
  }

  Future<void> _sendResetLink() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    setState(() {
      _isSending = false;
      _showSuccess = true;
    });
    _startResendCountdown();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _secondsRemaining = 45);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _resendLink() async {
    if (_secondsRemaining > 0) return;
    setState(() => _isSending = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isSending = false);
    _startResendCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _navy,
        content: Text(
          'Demo: reset link request repeated. Backend email delivery is not connected.',
          style: _style(size: 12, color: Colors.white),
        ),
      ),
    );
  }

  void _returnToInput() {
    _resendTimer?.cancel();
    setState(() {
      _showSuccess = false;
      _secondsRemaining = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _showSuccess ? _successContent() : _formContent(),
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _background.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: IconButton(
              onPressed: _backToSignIn,
              tooltip: 'Go back',
              icon: const Icon(Icons.arrow_back, color: _text, size: 22),
            ),
          ),
          Expanded(
            child: Text(
              'Forgot Password',
              textAlign: TextAlign.center,
              style: _style(size: 17, weight: FontWeight.w700),
            ),
          ),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: _navy,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _backAndBadge() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25, top: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: _backToSignIn,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back, color: _teal, size: 18),
                  const SizedBox(width: 5),
                  Text(
                    'Back to Sign In',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: _teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFD3E5F1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: _secondaryText,
                ),
                const SizedBox(width: 5),
                Text(
                  'SSO GUARD',
                  style: _style(
                    size: 10,
                    weight: FontWeight.w800,
                    color: _secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero({required bool success}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: _mint,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _teal.withValues(alpha: 0.12),
                  blurRadius: 22,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 57,
                height: 57,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.mark_email_read : Icons.lock_reset,
                  color: _teal,
                  size: 31,
                ),
              ),
            ),
          ),
          const SizedBox(height: 17),
          Text(
            success ? 'Reset instructions sent!' : 'Reset your password',
            textAlign: TextAlign.center,
            style: _style(size: 25, weight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            success
                ? 'We have prepared your secure password reset instructions.'
                : 'Enter your registered work email to receive a secure, one-time verification link.',
            textAlign: TextAlign.center,
            style: _style(size: 13, color: _secondaryText, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _formContent() {
    return Column(
      key: const ValueKey('forgot-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backAndBadge(),
        _hero(success: false),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.045),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Work Email Address',
                      style: _style(size: 13, weight: FontWeight.w700),
                    ),
                    Text(
                      'Enterprise SSO',
                      style: _style(
                        size: 10,
                        weight: FontWeight.w700,
                        color: _teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  style: _style(size: 14),
                  decoration: InputDecoration(
                    hintText: 'name@company.com',
                    hintStyle: _style(size: 13, color: _outline),
                    prefixIcon: const Icon(
                      Icons.mail_outline,
                      color: _outline,
                      size: 21,
                    ),
                    filled: true,
                    fillColor: _surfaceBlue,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _teal, width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                        color: Color(0xFFBA1A1A),
                        width: 1.5,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return 'Enter a valid work email address';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _sendResetLink(),
                ),
                const SizedBox(height: 17),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _surfaceBlue,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: _teal,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Links expire in 15 minutes for cryptographic credential security and tamper prevention.',
                          style: _style(
                            size: 11,
                            color: _secondaryText,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendResetLink,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Send Reset Link',
                                style: _style(
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Remembered your credentials?',
          textAlign: TextAlign.center,
          style: _style(size: 12, color: _secondaryText),
        ),
        TextButton(
          onPressed: _backToSignIn,
          child: Text(
            'Return to Sign In',
            style: _style(size: 13, weight: FontWeight.w700, color: _navy),
          ),
        ),
      ],
    );
  }

  Widget _successContent() {
    final email = _emailController.text.trim();
    return Column(
      key: const ValueKey('forgot-success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: _teal, size: 16),
                const SizedBox(width: 6),
                Text(
                  'TRANSMISSION DISPATCHED',
                  style: _style(
                    size: 10,
                    weight: FontWeight.w800,
                    color: _teal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _hero(success: true),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.045),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                "We've dispatched a secure, one-time authentication link to ${_maskedEmail(email)}.",
                textAlign: TextAlign.center,
                style: _style(size: 13, color: _secondaryText, height: 1.6),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceBlue,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: _navy, size: 18),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Please check your inbox and corporate quarantine filter. Ensure the sender signature matches auth@brandguard.io.',
                        style: _style(
                          size: 11,
                          color: _secondaryText,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 19),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Email app opening requires a configured email app.',
                        style: _style(size: 12, color: Colors.white),
                      ),
                      backgroundColor: _navy,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    'Open Email App',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _secondsRemaining == 0 && !_isSending
                      ? _resendLink
                      : null,
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text(
                    _isSending
                        ? 'Sending...'
                        : _secondsRemaining > 0
                        ? 'Resend Link (0:${_secondsRemaining.toString().padLeft(2, '0')})'
                        : 'Resend Link',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: _secondsRemaining > 0 ? _outline : _teal,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _surfaceBlue,
                    foregroundColor: _teal,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: TextButton.icon(
            onPressed: _returnToInput,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(
              'Return to Sign In',
              style: _style(size: 13, weight: FontWeight.w700, color: _teal),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 14, color: _outline),
              const SizedBox(width: 6),
              Text(
                '256-BIT VAULT PROTOCOL',
                style: _style(
                  size: 10,
                  weight: FontWeight.w800,
                  color: _outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'BrandGuard Pre-Publication Governance • Zero Trust Identity',
            textAlign: TextAlign.center,
            style: _style(size: 10, color: _outline),
          ),
        ],
      ),
    );
  }
}
