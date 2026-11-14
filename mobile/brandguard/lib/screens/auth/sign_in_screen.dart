import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'create_account_screen.dart';
import 'forgot_password_screen.dart';
import '../dashboard/home_dashboard_screen.dart';

class BrandColors {
  static const navy = Color(0xFF142C3B);
  static const darkNavy = Color(0xFF001725);
  static const teal = Color(0xFF006B5E);
  static const brightTeal = Color(0xFF22A895);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF4FAFF);
  static const lightBlue = Color(0xFFE8F6FF);
  static const border = Color(0xFFE5ECE9);
  static const text = Color(0xFF0C1E26);
  static const secondaryText = Color(0xFF73787C);
  static const white = Colors.white;
  static const error = Color(0xFFD95D5D);
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController(
    text: 'elena.vance@lumina-brand.io',
  );

  final _passwordController = TextEditingController();

  bool _passwordVisible = false;
  bool _rememberNode = true;
  bool _isLoading = false;

  bool get _isValidDomain {
    final email = _emailController.text.trim();
    final parts = email.split('@');

    return parts.length == 2 &&
        parts[1].contains('.') &&
        parts[1].indexOf('.') > 0;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('bg_profile_email');
      if (!mounted || savedEmail == null || savedEmail.trim().isEmpty) return;
      setState(() {
        _emailController.text = savedEmail.trim();
      });
    } catch (_) {
      // Keep the default demo email if local preferences are unavailable.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String title, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: BrandColors.navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  color: BrandColors.mint,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _openCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateAccountScreen(),
      ),
    );
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Keep the entered email in the local demo profile.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_profile_email', _emailController.text.trim());

    if (!mounted) return;

    // Demo authentication delay.
    // Real authentication API will be integrated later.
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    setState(() => _isLoading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeDashboardScreen(),
      ),
    );
  }

  void _samlSignIn() {
    _showMessage(
      'Handshaking Okta SAML',
      'Resolving organization claims metadata... Backend integration pending.',
    );
  }

  void _resetAccess() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ForgotPasswordScreen(),
      ),
    );
  }

  void _requestClearance() {
    _showMessage(
      'Request Clearance',
      'Organization clearance request flow will be connected later.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 46,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 34),
                    _welcomeSection(),
                    const SizedBox(height: 26),
                    _authenticationCard(),
                    const SizedBox(height: 22),
                    _roleEnforcementCard(),
                    const SizedBox(height: 25),
                    _clearanceSection(),
                    const SizedBox(height: 12),
                    _createAccountSection(),
                    const SizedBox(height: 24),
                    _footer(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: BrandColors.darkNavy,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: BrandColors.navy.withValues(alpha: 0.12),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.verified_user_rounded,
            color: BrandColors.brightTeal,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            Text(
              'BrandGuard',
              style: _style(
                size: 21,
                weight: FontWeight.w800,
                color: BrandColors.darkNavy,
                letterSpacing: -0.8,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 3, top: 2),
              child: Icon(
                Icons.circle,
                size: 8,
                color: BrandColors.teal,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFD8EBF7),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.circle,
                size: 9,
                color: BrandColors.teal,
              ),
              const SizedBox(width: 7),
              Text(
                'VAULT V2.4',
                style: _style(
                  size: 11,
                  weight: FontWeight.w700,
                  color: BrandColors.navy,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _welcomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back',
          style: _style(
            size: 29,
            weight: FontWeight.w800,
            color: BrandColors.darkNavy,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Sign in to protect and audit your brand assets.',
          style: _style(
            size: 14,
            color: BrandColors.secondaryText,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _authenticationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: BrandColors.border.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: BrandColors.navy.withValues(alpha: 0.045),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _enterpriseHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 19),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel(
                    'Work Email',
                    trailing: _isValidDomain
                        ? 'Verified Tenant'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _emailField(),
                  const SizedBox(height: 22),
                  _fieldLabel('Password'),
                  const SizedBox(height: 8),
                  _passwordField(),
                  const SizedBox(height: 17),
                  _rememberRow(),
                  const SizedBox(height: 23),
                  _primaryButton(),
                  const SizedBox(height: 25),
                  _divider(),
                  const SizedBox(height: 20),
                  _samlButton(),
                  const SizedBox(height: 16),
                  _zeroTrustNote(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _enterpriseHeader() {
    return Container(
      color: BrandColors.lightBlue,
      padding: const EdgeInsets.symmetric(
        horizontal: 17,
        vertical: 15,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.domain_rounded,
            size: 20,
            color: BrandColors.teal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Enterprise Domain Auth',
              style: _style(
                size: 13,
                weight: FontWeight.w700,
                color: BrandColors.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFD3E5F1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'SHA-256',
              style: _style(
                size: 11,
                weight: FontWeight.w800,
                color: BrandColors.darkNavy,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String title, {String? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: _style(
            size: 13,
            weight: FontWeight.w700,
            color: BrandColors.darkNavy,
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: _style(
              size: 11,
              weight: FontWeight.w600,
              color: BrandColors.teal,
            ),
          ),
      ],
    );
  }

  Widget _emailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      style: _style(
        size: 14,
        color: BrandColors.text,
      ),
      validator: (value) {
        final email = value?.trim() ?? '';

        if (email.isEmpty || !email.contains('@')) {
          return 'Enter a valid work email';
        }

        if (!email.split('@').last.contains('.')) {
          return 'Enter a valid email domain';
        }

        return null;
      },
      decoration: _inputDecoration(
        hint: 'name@company.com',
        icon: Icons.mail_outline_rounded,
      ),
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_passwordVisible,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _signIn(),
      style: _style(
        size: 14,
        color: BrandColors.text,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Enter your security passphrase';
        }

        return null;
      },
      decoration: _inputDecoration(
        hint: 'Enter security passphrase',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          tooltip: _passwordVisible
              ? 'Hide password'
              : 'Show password',
          onPressed: () {
            setState(() {
              _passwordVisible = !_passwordVisible;
            });
          },
          icon: Icon(
            _passwordVisible
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            color: BrandColors.secondaryText,
            size: 21,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _style(
        size: 13,
        color: BrandColors.secondaryText,
      ),
      prefixIcon: Icon(
        icon,
        size: 21,
        color: BrandColors.teal,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: BrandColors.lightBlue,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: BrandColors.border.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: BrandColors.teal,
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: BrandColors.error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: BrandColors.error,
          width: 1.4,
        ),
      ),
    );
  }

  Widget _rememberRow() {
    return Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: _rememberNode,
            activeColor: BrandColors.teal,
            side: const BorderSide(
              color: BrandColors.secondaryText,
              width: 1.2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            onChanged: (value) {
              setState(() {
                _rememberNode = value ?? false;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Remember node',
            style: _style(
              size: 12,
              color: BrandColors.secondaryText,
            ),
          ),
        ),
        TextButton(
          onPressed: _resetAccess,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.teal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          child: Text(
            'Reset Access?',
            style: _style(
              size: 12,
              weight: FontWeight.w700,
              color: BrandColors.teal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      height: 51,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.darkNavy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: BrandColors.navy,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
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
                    'Sign In to Dashboard',
                    style: _style(
                      size: 14,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 21,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            color: Color(0xFFD8EBF7),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR ENTERPRISE SIGN IN',
            style: _style(
              size: 10,
              weight: FontWeight.w700,
              color: BrandColors.secondaryText,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: Color(0xFFD8EBF7),
          ),
        ),
      ],
    );
  }

  Widget _samlButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _samlSignIn,
        style: OutlinedButton.styleFrom(
          backgroundColor: BrandColors.lightBlue,
          foregroundColor: BrandColors.darkNavy,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.security_rounded,
              color: BrandColors.teal,
              size: 22,
            ),
            const SizedBox(width: 11),
            Text(
              'Continue with SAML 2.0 (Okta)',
              style: _style(
                size: 13,
                weight: FontWeight.w700,
                color: BrandColors.darkNavy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zeroTrustNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: BrandColors.secondaryText,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Zero-trust authenticated session via Cloudflare TLS',
            textAlign: TextAlign.center,
            style: _style(
              size: 10,
              weight: FontWeight.w600,
              color: BrandColors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _roleEnforcementCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BrandColors.lightBlue,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: BrandColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: BrandColors.teal,
              size: 21,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Role-Based Access Enforcement',
                  style: _style(
                    size: 13,
                    weight: FontWeight.w700,
                    color: BrandColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Role credentials (Audit Director, Legal Reviewer, Agency Contributor) are provisioned through your organization’s identity provider directory.',
                  style: _style(
                    size: 12,
                    color: BrandColors.secondaryText,
                    height: 1.65,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _clearanceSection() {
    return Column(
      children: [
        Text(
          'New organization requiring clearance?',
          textAlign: TextAlign.center,
          style: _style(
            size: 13,
            color: BrandColors.text,
          ),
        ),
        const SizedBox(height: 5),
        TextButton(
          onPressed: _requestClearance,
          child: Text(
            'Request Clearance',
            style: _style(
              size: 13,
              weight: FontWeight.w800,
              color: BrandColors.teal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _createAccountSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'New to BrandGuard?',
          style: _style(
            size: 13,
            color: BrandColors.secondaryText,
          ),
        ),
        TextButton(
          onPressed: _openCreateAccount,
          child: Text(
            'Create Account',
            style: _style(
              size: 13,
              weight: FontWeight.w800,
              color: BrandColors.teal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _footerLabel('Security Ledger'),
        _footerDot(),
        _footerLabel('SOC2 Compliance'),
        _footerDot(),
        _footerLabel('Privacy Seal'),
      ],
    );
  }

  Widget _footerLabel(String label) {
    return Flexible(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: _style(
          size: 9,
          weight: FontWeight.w700,
          color: BrandColors.secondaryText,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _footerDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: _style(
          size: 11,
          color: BrandColors.secondaryText,
        ),
      ),
    );
  }

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = BrandColors.text,
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}