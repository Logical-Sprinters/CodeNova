import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';
import '../../core/network/document_picker.dart';

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

  String? _verifyAtIso;
  String _verifyAtLabel = 'Now';
  String? _verifyFileName;
  Uint8List? _verifyFileBytes;

  bool _isLoading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _checkIdCtrl.dispose();
    _brandNameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAssetForVerify() async {
    try {
      final picked = await pickLocalFileBytes(
        extensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf', 'txt', 'md'],
      );
      if (picked == null || !mounted) return;
      setState(() {
        _verifyFileName = picked.name;
        _verifyFileBytes = picked.bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = {'valid': false, 'reason': e.toString()});
    }
  }

  Future<void> _pickCustomVerifyDate() async {
    final ctrl = TextEditingController(
      text: _verifyAtIso ?? '2026-11-18T12:00:00Z',
    );
    final route = DialogRoute<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify effective date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check whether this approval seal was valid at an ISO-8601 timestamp (e.g. 2026-10-15T12:00:00Z).',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'ISO-8601 timestamp',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    try {
      final chosen = await Navigator.of(context).push(route);
      if (chosen != null && chosen.isNotEmpty && mounted) {
        setState(() {
          _verifyAtIso = chosen;
          _verifyAtLabel = chosen.length > 10 ? chosen.substring(0, 10) : chosen;
        });
      }
    } finally {
      await route.completed;
      ctrl.dispose();
    }
  }

  Future<void> _verify() async {
    if (_checkIdCtrl.text.trim().isEmpty ||
        (_contentCtrl.text.trim().isEmpty && _verifyFileBytes == null)) {
      setState(
        () => _result = {
          'valid': false,
          'reason':
              'Check ID and either exact content text or an asset file are required.',
        },
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> resp;
      if (_verifyFileBytes != null && _verifyFileName != null) {
        resp = await BrandGuardApiService.verifyApprovalUpload(
          checkId: _checkIdCtrl.text.trim(),
          brandName: _brandNameCtrl.text.trim(),
          content: _contentCtrl.text.isEmpty ? null : _contentCtrl.text,
          fileName: _verifyFileName!,
          bytes: _verifyFileBytes!,
          verifyAt: _verifyAtIso,
        );
      } else {
        resp = await BrandGuardApiService.verifyApproval(
          checkId: _checkIdCtrl.text.trim(),
          brandName: _brandNameCtrl.text.trim(),
          content: _contentCtrl.text,
          verifyAt: _verifyAtIso,
        );
      }
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
    final sealStatus = _result?['seal_status']?.toString();
    final tamperedTokens = (_result?['tampered_tokens'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final ruleChanges = (_result?['rule_changes'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final diffSegments = (_result?['diff_segments'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    const datePresets = <(String, String?)>[
      ('Now', null),
      ('Oct 2026', '2026-10-15T12:00:00Z'),
      ('Nov 2026', '2026-11-15T12:00:00Z'),
    ];

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
              eyebrow: 'COMPOSITE CRYPTOGRAPHIC SEAL',
              eyebrowTone: Tone.info,
              title: 'Approval verification',
              subtitle:
                  'Verify exact caption, attached banner assets, active rule versions, and point-in-time validity.',
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
                      hintText:
                          'Paste the content exactly as it was approved — spacing and punctuation matter.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('VERIFY AT (TIME-TRAVEL)', style: AppTheme.monoLabel()),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in datePresets)
                        GestureDetector(
                          onTap: () => setState(() {
                            _verifyAtIso = preset.$2;
                            _verifyAtLabel = preset.$1;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _verifyAtLabel == preset.$1
                                  ? AppTheme.mint
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _verifyAtLabel == preset.$1
                                    ? AppTheme.teal
                                    : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              preset.$1,
                              style: AppTheme.monoLabel(
                                color: _verifyAtLabel == preset.$1
                                    ? AppTheme.tealText
                                    : AppTheme.ink,
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: _pickCustomVerifyDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 12,
                                color: AppTheme.ink,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Custom ISO',
                                style: AppTheme.monoLabel(color: AppTheme.ink),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SEALED ASSET FILE',
                          style: AppTheme.monoLabel(),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isLoading ? null : _pickAssetForVerify,
                        icon: const Icon(Icons.image_search_outlined, size: 16),
                        label: const Text('Upload file'),
                      ),
                    ],
                  ),
                  if (_verifyFileName != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: AppTheme.tealText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _verifyFileName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.monoLabel(color: AppTheme.ink),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() {
                              _verifyFileName = null;
                              _verifyFileBytes = null;
                            }),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      key: const ValueKey('verify-approval-submit'),
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
                      label: Text(
                        _verifyFileBytes != null
                            ? 'Verify uploaded seal'
                            : 'Verify against server',
                      ),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          valid
                              ? Icons.verified_rounded
                              : Icons.gpp_bad_rounded,
                          color: valid ? AppTheme.success : AppTheme.danger,
                          size: 20,
                        ),
                        StatusPill(
                          label: sealStatus ?? (valid ? 'SEALED' : 'Invalid'),
                          tone: valid ? Tone.success : Tone.danger,
                          solid: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      valid
                          ? 'Approval seal is cryptographically valid'
                          : sealStatus == 'REVOKED'
                          ? 'Approval seal was revoked by reviewer'
                          : 'Approval invalid / tampered or stale',
                      style: AppTheme.labelLarge.copyWith(
                        color: valid ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _result!['reason']?.toString() ?? 'No reason returned.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                    ),
                    if (sealStatus == 'REVOKED' &&
                        (_result!['revoked_at']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Revoked at ${_result!['revoked_at']}',
                        style: AppTheme.monoLabel(color: AppTheme.muted),
                      ),
                    ],
                    if (diffSegments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'WORD-LEVEL TAMPER DIFF',
                        style: AppTheme.monoLabel(color: AppTheme.danger),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                            children: diffSegments.expand((seg) {
                              final op = seg['op']?.toString() ?? 'equal';
                              final oldTxt = seg['approved_text']?.toString() ?? '';
                              final newTxt = seg['current_text']?.toString() ?? '';
                              if (op == 'equal') {
                                return [TextSpan(text: oldTxt)];
                              }
                              return [
                                if (oldTxt.isNotEmpty)
                                  TextSpan(
                                    text: oldTxt,
                                    style: TextStyle(
                                      color: AppTheme.danger,
                                      backgroundColor: AppTheme.dangerBg,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                if (newTxt.isNotEmpty)
                                  TextSpan(
                                    text: newTxt,
                                    style: TextStyle(
                                      color: AppTheme.tealText,
                                      backgroundColor: AppTheme.mint,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ];
                            }).toList(),
                          ),
                        ),
                      ),
                    ] else if (tamperedTokens.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tamperedTokens
                            .map(
                              (t) => StatusPill(
                                label: t['label']?.toString() ?? 'tampered',
                                tone: Tone.danger,
                                compact: true,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (ruleChanges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'CHANGED RULES SINCE SIGN-OFF',
                        style: AppTheme.monoLabel(color: AppTheme.warning),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ruleChanges
                            .map(
                              (rc) => StatusPill(
                                label:
                                    '${rc['rule_id'] ?? 'rule'}: ${rc['status'] ?? rc['reason'] ?? 'changed'}',
                                tone: Tone.warning,
                                compact: true,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (_result!.length > 2) ...[
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      ..._result!.entries
                          .where(
                            (e) =>
                                e.key != 'valid' &&
                                e.key != 'reason' &&
                                e.key != 'seal_status' &&
                                e.key != 'diff_segments' &&
                                e.key != 'tampered_tokens' &&
                                e.key != 'rule_changes' &&
                                e.key != 'unified_diff',
                          )
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
              title: 'Why a composite seal can fail honestly',
              message:
                  'Changing even 1 pixel of an approved banner, editing a single character of caption, bumping a rule version, or verifying outside effective dates invalidates the seal.',
            ),
          ],
        ),
      ),
    );
  }
}
