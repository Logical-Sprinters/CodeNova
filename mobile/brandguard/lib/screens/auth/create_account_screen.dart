import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sign_in_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _orgController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _acceptedTerms = true;
  bool _isLoading = false;

  static const navy = Color(0xFF001725);
  static const teal = Color(0xFF006B5E);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF4FAFF);
  static const fieldBackground = Color(0xFFFFFFFF);
  static const cardBlue = Color(0xFFE8F6FF);
  static const secondaryText = Color(0xFF73787C);
  static const border = Color(0xFFE5ECE9);
  static const error = Color(0xFFBA1A1A);

  String get _password => _passwordController.text;

  bool get _hasMinLength => _password.length >= 8;
  bool get _hasUppercase => _password.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _password.contains(RegExp(r'[0-9]'));
  bool get _hasSymbol => _password.contains(RegExp(r'[^A-Za-z0-9]'));

  int get _strength => [
    _hasMinLength,
    _hasUppercase,
    _hasNumber,
    _hasSymbol,
  ].where((value) => value).length;

  String get _strengthLabel {
    if (_strength <= 1) return 'WEAK';
    if (_strength == 2) return 'FAIR';
    if (_strength == 3) return 'STRONG';
    return 'VERY STRONG';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _orgController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = navy,
    double? height,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  void _message(String title, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        content: Text(
          '$title\n$message',
          style: _style(color: Colors.white, size: 12),
        ),
      ),
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      _message(
        'Terms required',
        'Please accept the Terms of Service and Brand Governance Protocols.',
      );
      return;
    }

    setState(() => _isLoading = true);

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    try {
      // Save the basic profile details locally for this frontend demo.
      // Passwords are intentionally not stored in SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bg_profile_name', _nameController.text.trim());
      await prefs.setString('bg_profile_email', _emailController.text.trim());
      await prefs.setString(
        'bg_profile_organization',
        _orgController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      // Return to the Sign In page after account creation.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _message(
        'Unable to save account details',
        'Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _intro(),
                      const SizedBox(height: 25),
                      _accessNotice(),
                      const SizedBox(height: 27),
                      _nameField(),
                      const SizedBox(height: 20),
                      _emailField(),
                      const SizedBox(height: 20),
                      _organisationField(),
                      const SizedBox(height: 20),
                      _passwordField(),
                      const SizedBox(height: 19),
                      _confirmPasswordField(),
                      const SizedBox(height: 22),
                      _termsRow(),
                      const SizedBox(height: 26),
                      _createButton(),
                      const SizedBox(height: 25),
                      _signInLink(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_rounded, color: navy),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Sign Up',
                style: _style(size: 18, weight: FontWeight.w700),
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: navy,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro() {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: 0.10),
                blurRadius: 9,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.shield_rounded, color: mint, size: 37),
        ),
        const SizedBox(height: 19),
        Text(
          'Create your account',
          textAlign: TextAlign.center,
          style: _style(size: 25, weight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          'Get started with BrandGuard.',
          style: _style(size: 15, color: secondaryText),
        ),
      ],
    );
  }

  Widget _accessNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDFF1FC),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(color: navy.withValues(alpha: 0.035), blurRadius: 7),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: teal, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEFAULT CREATOR ACCESS',
                  style: _style(size: 13, weight: FontWeight.w800, color: teal),
                ),
                const SizedBox(height: 7),
                Text(
                  'Administrative and Authorised Reviewer roles are granted strictly via organisation administrator approval following pre-publication protocols.',
                  style: _style(
                    size: 13,
                    color: const Color(0xFF43474C),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: _style(size: 14, weight: FontWeight.w700)),
    );
  }

  InputDecoration _decoration({
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _style(size: 14, color: secondaryText),
      prefixIcon: Icon(icon, color: const Color(0xFF43474C), size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: border.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: teal, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: error, width: 1.4),
      ),
    );
  }

  Widget _nameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Full Name'),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            icon: Icons.person_outline_rounded,
            hint: 'Elena Rostova',
          ),
          validator: (value) {
            if (value == null || value.trim().length < 2) {
              return 'Enter your full name';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _emailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Work Email (Corporate Domain)'),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            icon: Icons.mail_outline_rounded,
            hint: 'elena@apexcloud.io',
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid work email';
            }
            return null;
          },
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(Icons.info_outline, color: teal, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "Must match your company's registered domain",
                style: _style(size: 12, color: secondaryText),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _organisationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Organisation Name'),
        TextFormField(
          controller: _orgController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            icon: Icons.business_outlined,
            hint: 'Apex Technologies Inc.',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Enter your organisation name';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Password'),
        TextFormField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            icon: Icons.lock_outline_rounded,
            hint: 'Create a strong password',
            suffix: IconButton(
              onPressed: () {
                setState(() => _passwordVisible = !_passwordVisible);
              },
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: secondaryText,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.length < 8) {
              return 'Password must contain at least 8 characters';
            }
            if (!_hasUppercase || !_hasNumber || !_hasSymbol) {
              return 'Add uppercase, number and symbol';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        _passwordStrength(),
      ],
    );
  }

  Widget _passwordStrength() {
    final colors = [
      const Color(0xFFD95D5D),
      const Color(0xFFE6A23C),
      teal,
      teal,
    ];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cardBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STRENGTH: ${_password.isEmpty ? '—' : _strengthLabel}',
                style: _style(size: 12, weight: FontWeight.w800, color: teal),
              ),
              Text(
                '$_strength of 4',
                style: _style(size: 12, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(4, (index) {
              return Expanded(
                child: Container(
                  height: 7,
                  margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
                  decoration: BoxDecoration(
                    color: index < _strength
                        ? colors[_strength - 1 < 0 ? 0 : _strength - 1]
                        : const Color(0xFFD3E5F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.check_circle_outline, color: teal, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '8+ chars, uppercase, number, symbol',
                  style: _style(size: 12, color: secondaryText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Confirm Password'),
        TextFormField(
          controller: _confirmController,
          obscureText: !_confirmVisible,
          textInputAction: TextInputAction.done,
          decoration: _decoration(
            icon: Icons.lock_reset_rounded,
            hint: 'Confirm your password',
            suffix: IconButton(
              onPressed: () {
                setState(() => _confirmVisible = !_confirmVisible);
              },
              icon: Icon(
                _confirmVisible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: secondaryText,
              ),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Confirm your password';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _termsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _acceptedTerms,
          activeColor: teal,
          checkColor: Colors.white,
          side: const BorderSide(color: teal, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          onChanged: (value) {
            setState(() => _acceptedTerms = value ?? false);
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                style: _style(size: 13, color: secondaryText, height: 1.5),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: teal,
                    ),
                  ),
                  const TextSpan(text: ', '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: teal,
                    ),
                  ),
                  const TextSpan(text: ', and '),
                  TextSpan(
                    text: 'Brand Governance Protocols',
                    style: _style(
                      size: 13,
                      weight: FontWeight.w700,
                      color: teal,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _createButton() {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _createAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: teal.withValues(alpha: 0.6),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Create Account',
                    style: _style(
                      size: 16,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward_rounded),
                ],
              ),
      ),
    );
  }

  Widget _signInLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: _style(size: 14, color: secondaryText),
        ),
        TextButton(
          onPressed: _goBack,
          style: TextButton.styleFrom(
            foregroundColor: teal,
            padding: const EdgeInsets.symmetric(horizontal: 3),
          ),
          child: Text(
            'Sign In',
            style: _style(size: 14, weight: FontWeight.w800, color: teal),
          ),
        ),
      ],
    );
  }
}
