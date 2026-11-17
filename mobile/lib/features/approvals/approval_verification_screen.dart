import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';

class ApprovalVerificationScreen extends StatefulWidget {
  const ApprovalVerificationScreen({super.key});

  @override
  State<ApprovalVerificationScreen> createState() =>
      _ApprovalVerificationScreenState();
}

class _ApprovalVerificationScreenState
    extends State<ApprovalVerificationScreen> {
  final _checkIdCtrl = TextEditingController();
  final _brandNameCtrl = TextEditingController(text: 'Acme');
  final _contentCtrl = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _checkIdCtrl.dispose();
    _brandNameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_checkIdCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      setState(
        () => _result = {
          'valid': false,
          'reason': 'Check ID and the exact content text are both required.',
        },
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final resp = await BrandGuardApiService.verifyApproval(
        checkId: _checkIdCtrl.text.trim(),
        brandName: _brandNameCtrl.text.trim(),
        content: _contentCtrl.text,
      );
      if (!mounted) return;
      setState(() => _result = resp);
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = {'valid': false, 'reason': e.toString()});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final valid = _result?['valid'] == true;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Verify approval'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
          children: [
            const PageIntro(
              eyebrow: 'ZERO AMBIGUITY RULE',
              eyebrowTone: Tone.info,
              title: 'Approval verification',
              subtitle: 'Check whether an approval still binds this exact text and the current rule version.',
            ),
            const SizedBox(height: 14),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _checkIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Check ID',
                      prefixIcon: Icon(Icons.badge_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _brandNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      prefixIcon: Icon(Icons.storefront_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Exact approved content',
                      alignLabelWithHint: true,
                      hintText: 'Paste the content exactly as it was approved — spacing and punctuation matter.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _verify,
                      icon: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.verified_user_outlined, size: 18),
                      label: const Text('Verify against server'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_result != null)
              SurfaceCard(
                borderColor: (valid ? AppTheme.success : AppTheme.danger)
                    .withValues(alpha: 0.35),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          valid
                              ? Icons.verified_rounded
                              : Icons.gpp_bad_rounded,
                          color: valid ? AppTheme.success : AppTheme.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            valid
                                ? 'Approval is valid for this text'
                                : 'Approval not valid',
                            style: AppTheme.labelLarge.copyWith(
                              color: valid ? AppTheme.success : AppTheme.danger,
                            ),
                          ),
                        ),
                        StatusPill(
                          label: valid ? 'Valid' : 'Invalid',
                          tone: valid ? Tone.success : Tone.danger,
                          solid: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _result!['reason']?.toString() ?? 'No reason returned.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                    ),
                    if (_result!.length > 2) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      ..._result!.entries
                          .where((e) => e.key != 'valid' && e.key != 'reason')
                          .map(
                            (e) => DetailRow(
                              label: e.key.replaceAll('_', ' '),
                              value: e.value?.toString() ?? '—',
                              monospace: true,
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            const InlineNotice(
              tone: Tone.warning,
              title: 'Why this can fail honestly',
              message: 'Any edit after sign-off, or a newer rules version, invalidates an approval. A failed verification means a new review is required — not that the content is safe to publish.',
            ),
          ],
        ),
      ),
    );
  }
}
