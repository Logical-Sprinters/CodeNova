import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';

/// Password reset request. The UI never claims an email was delivered: the
/// backend decides, and a local-only server honestly reports that email reset
/// is unavailable.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BrandGuardApiService.recover(_email.text);
      if (!mounted) return;
      Navigator.pop(context, true);
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
    AppTheme.watch(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Forgot Password'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: BrandMark(size: 34, radius: 10),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Sign In'),
                ),
                const StatusPill(
                  label: 'Email verification',
                  tone: Tone.info,
                  icon: Icons.mark_email_read_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppTheme.mint,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.teal.withValues(alpha: 0.35),
                    width: 4,
                  ),
                ),
                child: Icon(
                  Icons.lock_reset_rounded,
                  color: AppTheme.tealText,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Reset your password',
              textAlign: TextAlign.center,
              style: AppTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your registered work email to request a one-time reset link.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Work email address',
                          style: AppTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // The pill must shrink with the label at large text
                      // scales instead of pushing the row out of the card.
                      Flexible(
                        child: StatusPill(
                          label: 'Server verified',
                          tone: Tone.neutral,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('recover-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'name@company.com',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const InlineNotice(
                    tone: Tone.info,
                    icon: Icons.timer_outlined,
                    title: 'Link lifetime is set by the provider',
                    message: 'Supabase Auth issues the reset link. This app cannot see the token and does not resend it automatically.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    InlineNotice(
                      tone: Tone.danger,
                      title: 'Reset request was not sent',
                      message: _error!,
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      key: const ValueKey('send-reset'),
                      onPressed: _busy ? null : _send,
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
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Send Reset Link',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    'Remembered your credentials?',
                    style: AppTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: () => Navigator.maybePop(context),
                    child: const Text('Return to Sign In'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'BrandGuard pre-publication governance · role-based access',
                    textAlign: TextAlign.center,
                    style: AppTheme.monoLabel().copyWith(fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
