import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';
import '../../core/network/document_picker.dart';
import 'findings_evidence_screen.dart';

class NewBrandCheckScreen extends StatefulWidget {
  const NewBrandCheckScreen({super.key, this.draft});
  final Map<String, dynamic>? draft;
  @override
  State<NewBrandCheckScreen> createState() => _NewBrandCheckScreenState();
}

class _NewBrandCheckScreenState extends State<NewBrandCheckScreen> {
  final _title = TextEditingController(text: 'Untitled draft');
  final _brand = TextEditingController(text: 'Acme');
  final _content = TextEditingController();
  final List<Map<String, dynamic>> _attachments = [];
  String? _draftId;
  int? _revision;
  bool _busy = false;

  // Phase 4: Shift-Left Pre-Flight, Temporal Check Date & Channel
  bool _liveRadarEnabled = true;
  bool _preflightBusy = false;
  Map<String, dynamic>? _preflightResult;
  Timer? _preflightTimer;
  String _channel = 'all';
  String? _checkAtIso;
  String _checkAtLabel = 'Now';

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _draftId = draft['id'] as String?;
      _revision = draft['revision'] as int?;
      _title.text = draft['title']?.toString() ?? 'Untitled draft';
      _brand.text = draft['brand_name']?.toString() ?? 'Acme';
      _content.text = draft['content']?.toString() ?? '';
      _attachments.addAll(
        (draft['attachments'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
    }
  }

  @override
  void dispose() {
    _preflightTimer?.cancel();
    _title.dispose();
    _brand.dispose();
    _content.dispose();
    super.dispose();
  }

  int get _wordCount {
    final text = _content.text.trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  int get _step {
    if (_content.text.trim().isEmpty) return _attachments.isEmpty ? 1 : 2;
    if (_attachments.isEmpty) return 2;
    return 3;
  }

  List<String> get _assetIds => _attachments
      .map((a) => a['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

  bool get _hasImages =>
      _attachments.any((a) => a['is_image'] == true);

  void _message(Object value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value.toString())));
    }
  }

  void _onDraftChanged() {
    setState(() {});
    _schedulePreflight();
  }

  void _schedulePreflight({Duration delay = const Duration(milliseconds: 550)}) {
    _preflightTimer?.cancel();
    if (!_liveRadarEnabled ||
        _content.text.trim().length < 3 ||
        _brand.text.trim().isEmpty) {
      if (mounted && _preflightResult != null && _content.text.trim().isEmpty) {
        setState(() => _preflightResult = null);
      }
      return;
    }
    _preflightTimer = Timer(delay, _runPreflight);
  }

  Future<void> _runPreflight() async {
    final text = _content.text;
    final brand = _brand.text.trim();
    if (text.trim().isEmpty || brand.isEmpty || !mounted) return;
    setState(() => _preflightBusy = true);
    try {
      final res = await BrandGuardApiService.preflightCheck(
        brandName: brand,
        content: text,
        channel: _channel,
        checkAt: _checkAtIso,
        assetIds: _assetIds,
      );
      if (!mounted) return;
      // Ignore mocks/responses that don't match the preflight payload shape.
      if (res['status'] is! String) {
        setState(() => _preflightBusy = false);
        return;
      }
      // Guard against stale async replies after subsequent typing.
      if (_content.text == text) {
        setState(() {
          _preflightResult = res;
          _preflightBusy = false;
        });
      } else {
        setState(() => _preflightBusy = false);
      }
    } catch (_) {
      if (mounted) setState(() => _preflightBusy = false);
    }
  }

  void _applyPreflightFix(Map<String, dynamic> finding) {
    final evidence = finding['evidence']?.toString() ?? '';
    final replacement = finding['replacement']?.toString() ?? '';
    final start = int.tryParse(finding['start_index']?.toString() ?? '');
    final end = int.tryParse(finding['end_index']?.toString() ?? '');
    if (evidence.isEmpty || replacement.isEmpty) return;

    final current = _content.text;
    var applied = false;
    if (start != null &&
        end != null &&
        start >= 0 &&
        end <= current.length &&
        current.substring(start, end) == evidence) {
      _content.text = current.replaceRange(start, end, replacement);
      applied = true;
    } else {
      final idx = current.indexOf(evidence);
      if (idx >= 0) {
        _content.text = current.replaceRange(idx, idx + evidence.length, replacement);
        applied = true;
      }
    }
    if (applied) {
      setState(() {});
      _schedulePreflight(delay: const Duration(milliseconds: 120));
      _message('Applied fix: "$evidence" -> "$replacement"');
    }
  }

  Future<void> _pickCustomDate() async {
    final ctrl = TextEditingController(
      text: _checkAtIso ?? '2026-10-15T12:00:00Z',
    );
    final route = DialogRoute<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Point-in-time check date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter an ISO-8601 timestamp (e.g. 2026-10-15T12:00:00Z) to evaluate rules active at that exact moment.',
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
          _checkAtIso = chosen;
          _checkAtLabel = chosen.length > 10 ? chosen.substring(0, 10) : chosen;
        });
        _schedulePreflight(delay: const Duration(milliseconds: 100));
      }
    } finally {
      await route.completed;
      ctrl.dispose();
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    _preflightTimer?.cancel();
    setState(() => _busy = true);
    try {
      final serverAttachments = _attachments
          .map((a) => {'id': a['id'], 'name': a['name']})
          .toList();
      final result = await BrandGuardApiService.saveDraft({
        'title': _title.text.trim().isEmpty
            ? 'Untitled draft'
            : _title.text.trim(),
        'brand_name': _brand.text.trim(),
        'content': _content.text,
        'attachments': serverAttachments,
        'expected_revision': ?_revision,
      }, id: _draftId);
      if (!mounted) return;
      setState(() {
        _draftId = result['id'].toString();
        _revision = result['revision'] as int;
      });
      _message('Draft saved to the server (revision $_revision).');
    } catch (e) {
      _message(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      final result = await pickAndUploadDocument(brandName: _brand.text.trim());
      if (result == null || !mounted) return;
      setState(() {
        _attachments.add({
          'id': result['id'],
          'name': result['name'],
          'is_image': result['is_image'] == true,
          'width': result['width'],
          'height': result['height'],
          'ocr_status': result['ocr_status'],
          'dominant_colors': result['dominant_colors'] ?? const [],
          'extracted_text': result['extracted_text'] ?? '',
          'local_bytes': result['_local_bytes'],
        });
      });
      final isImage = result['is_image'] == true;
      final text = result['extracted_text']?.toString() ?? '';
      if (!mounted) return;

      if (isImage) {
        _message(
          text.isEmpty
              ? 'Banner image attached for palette & logo inspection.'
              : 'Banner image attached (${text.length} OCR chars extracted).',
        );
        _schedulePreflight(delay: const Duration(milliseconds: 100));
        return;
      }

      final insert = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Document uploaded'),
          content: Text(
            'Extracted ${text.length} characters from ${result['name']}. Insert this text into the editor?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep attachment only'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Insert text'),
            ),
          ],
        ),
      );
      if (insert == true && mounted) {
        setState(
          () => _content.text = _content.text.isEmpty
              ? text
              : '${_content.text}\n\n$text',
        );
        _schedulePreflight(delay: const Duration(milliseconds: 100));
      }
      _message('Save the draft to retain its attachment reference.');
    } catch (e) {
      _message(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    _preflightTimer?.cancel();
    if (_content.text.trim().isEmpty || _brand.text.trim().isEmpty) {
      _message('Enter a brand and nonempty content.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final exactText = _content.text;
    final assetIds = _assetIds;
    try {
      final result = await BrandGuardApiService.checkBrand(
        brandName: _brand.text.trim(),
        content: exactText,
        contentType: _hasImages ? 'multimodal' : 'text',
        channel: _channel == 'all' ? null : _channel,
        checkAt: _checkAtIso,
        assetIds: assetIds.isEmpty ? null : assetIds,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FindingsEvidenceScreen(
            contentText: exactText,
            onContentUpdated: (text) {
              if (mounted) setState(() => _content.text = text);
            },
            checkId: result['check_id'].toString(),
            brandName: result['brand_name'].toString(),
            status: result['status'].toString(),
            findings: result['findings'] as List? ?? [],
            conflicts: result['conflicts'] as List? ?? [],
            ocrText: result['ocr_text']?.toString() ?? '',
            visualSummary: result['visual_summary'] as List? ?? [],
            assetIds: (result['asset_ids'] as List? ?? assetIds)
                .map((e) => e.toString())
                .toList(),
            channel: result['channel']?.toString() ?? _channel,
            checkAt: result['check_at']?.toString() ?? _checkAtIso,
            receiptId: result['receipt_id']?.toString(),
            contentVersion: result['content_version'] as int?,
            aiVerification: result['ai_verification'] is Map
                ? Map<String, dynamic>.from(result['ai_verification'] as Map)
                : null,
          ),
        ),
      );
    } catch (e) {
      _message('Brand check failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color? _parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final val = int.tryParse(cleaned, radix: 16);
    if (val == null) return null;
    return Color(0xFF000000 | val);
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
        title: Text(_draftId == null ? 'New brand check' : 'Edit saved draft'),
        actions: [
          TextButton.icon(
            key: const ValueKey('save-draft'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(_revision == null ? 'Draft' : 'Save · r$_revision'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final splitWide = constraints.maxWidth >= 860;
            if (!splitWide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
                children: [
                  ..._editorColumnChildren(),
                  const SizedBox(height: 16),
                  _liveRadarCard(),
                  const SizedBox(height: 18),
                  ..._assetsAndSubmitChildren(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 12, 26),
                    children: [
                      ..._editorColumnChildren(),
                      const SizedBox(height: 16),
                      ..._assetsAndSubmitChildren(),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 6, 16, 26),
                    children: [_liveRadarCard()],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _editorColumnChildren() {
    return [
      _stepStrip(),
      const SizedBox(height: 14),
      SurfaceCard(
        padding: const EdgeInsets.all(12),
        radius: 16,
        color: AppTheme.surfaceTint,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.auto_awesome_motion_outlined,
                size: 18,
                color: AppTheme.tealText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title.text.trim().isEmpty
                        ? 'Untitled draft'
                        : _title.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelLarge.copyWith(fontSize: 13),
                  ),
                  Text(
                    '${_brand.text.trim()} · $_channel · $_checkAtLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(
              label: _draftId == null ? 'Local' : 'Synced',
              tone: _draftId == null ? Tone.neutral : Tone.success,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('Draft copy / marketing message', style: AppTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('draft-title'),
        controller: _title,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Draft title',
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('check-brand'),
        controller: _brand,
        enabled: !_busy,
        onChanged: (_) => _onDraftChanged(),
        decoration: const InputDecoration(
          labelText: 'Brand',
          helperText: 'Acme ships starter rules. Reviewers can add another brand.',
          isDense: true,
          prefixIcon: Icon(Icons.storefront_outlined),
        ),
      ),
      const SizedBox(height: 10),
      _temporalAndChannelBar(),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('check-content'),
        controller: _content,
        enabled: !_busy,
        minLines: 8,
        maxLines: 24,
        maxLength: 200000,
        onChanged: (_) => _onDraftChanged(),
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          alignLabelWithHint: true,
          hintText: 'Paste the exact copy that will be published. The check hashes this text exactly as written.',
          border: OutlineInputBorder(),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _metaChip(Icons.notes_rounded, '$_wordCount words'),
          _metaChip(Icons.text_fields_rounded, '${_content.text.length} chars'),
          _metaChip(
            Icons.schedule_rounded,
            '~${((_wordCount / 200) * 60).ceil()}s read',
          ),
        ],
      ),
    ];
  }

  Widget _temporalAndChannelBar() {
    const channels = ['all', 'instagram', 'linkedin', 'email', 'web'];
    final datePresets = <(String, String?)>[
      ('Now', null),
      ('Oct 2026', '2026-10-15T12:00:00Z'),
      ('Nov 2026', '2026-11-15T12:00:00Z'),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TARGET CHANNEL', style: AppTheme.monoLabel()),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: channels.map((ch) {
                final selected = _channel == ch;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: _busy
                        ? null
                        : () {
                            setState(() => _channel = ch);
                            _schedulePreflight(
                              delay: const Duration(milliseconds: 100),
                            );
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.mint : AppTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? AppTheme.teal : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        ch.toUpperCase(),
                        style: AppTheme.monoLabel(
                          color: selected ? AppTheme.tealText : AppTheme.ink,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Text('POINT-IN-TIME EVALUATION DATE', style: AppTheme.monoLabel()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in datePresets)
                GestureDetector(
                  onTap: _busy
                      ? null
                      : () {
                          setState(() {
                            _checkAtIso = preset.$2;
                            _checkAtLabel = preset.$1;
                          });
                          _schedulePreflight(
                            delay: const Duration(milliseconds: 100),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _checkAtLabel == preset.$1
                          ? AppTheme.mint
                          : AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _checkAtLabel == preset.$1
                            ? AppTheme.teal
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      preset.$1,
                      style: AppTheme.monoLabel(
                        color: _checkAtLabel == preset.$1
                            ? AppTheme.tealText
                            : AppTheme.ink,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: _busy ? null : _pickCustomDate,
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
                      Icon(Icons.event_outlined, size: 12, color: AppTheme.ink),
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
        ],
      ),
    );
  }

  Widget _liveRadarCard() {
    final status = _preflightResult?['status']?.toString();
    final findings = (_preflightResult?['findings'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final conflicts = (_preflightResult?['conflicts'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final elapsedMs = _preflightResult?['elapsed_ms'];

    final Tone radarTone = switch (status) {
      'clean' => Tone.success,
      'warnings_detected' => Tone.warning,
      'conflict_detected' => Tone.danger,
      _ => Tone.info,
    };

    return SurfaceCard(
      borderColor: status == 'conflict_detected'
          ? AppTheme.warning.withValues(alpha: 0.45)
          : AppTheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, size: 18, color: AppTheme.tealText),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Live Rule Radar',
                  style: AppTheme.titleMedium.copyWith(fontSize: 15),
                ),
              ),
              if (elapsedMs != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: StatusPill(
                    label: '${elapsedMs}ms',
                    tone: Tone.neutral,
                    compact: true,
                  ),
                ),
              Switch(
                value: _liveRadarEnabled,
                onChanged: (v) {
                  setState(() => _liveRadarEnabled = v);
                  if (v) {
                    _schedulePreflight(delay: const Duration(milliseconds: 50));
                  }
                },
              ),
            ],
          ),
          Text(
            'Shift-Left co-pilot: runs stateless pre-flight checks as you type with zero DB writes.',
            style: AppTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (_preflightBusy)
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Scanning draft…', style: AppTheme.bodySmall),
              ],
            )
          else if (_preflightResult == null)
            InlineNotice(
              tone: Tone.neutral,
              title: 'Waiting for copy',
              message: 'Start typing or attach a banner to see live policy matches and 1-click fixes.',
            )
          else if (status == 'conflict_detected')
            InlineNotice(
              tone: Tone.warning,
              title: 'Internal rule conflict detected',
              message:
                  'Found ${conflicts.length} contradicting source(s). Run Brand Check to inspect side-by-side and escalate.',
            )
          else if (findings.isEmpty)
            InlineNotice(
              tone: Tone.success,
              title: 'Pre-flight clear',
              message: 'No active rule or verified-fact warnings detected on current copy.',
            )
          else ...[
            StatusPill(
              label: '${findings.length} live warning${findings.length == 1 ? '' : 's'}',
              tone: radarTone,
              solid: true,
              compact: true,
            ),
            if (_content.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              _highlightedDraftPreview(findings),
            ],
            const SizedBox(height: 10),
            for (final f in findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusPill(
                            label: '${f['rule_id']} v${f['rule_version'] ?? '1.0.0'}',
                            tone: Tone.warning,
                            compact: true,
                          ),
                          StatusPill(
                            label: f['source_origin']?.toString() ?? 'caption',
                            tone: Tone.info,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f['message']?.toString() ?? '',
                        style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                      ),
                      if ((f['rule_quote']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Rule quote: "${f['rule_quote']}"',
                          style: AppTheme.bodySmall,
                        ),
                      ],
                      if ((f['replacement']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.mint,
                              foregroundColor: AppTheme.tealText,
                            ),
                            onPressed: () => _applyPreflightFix(f),
                            icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
                            label: Text(
                              'Apply fix: ${f['replacement']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _highlightedDraftPreview(List<Map<String, dynamic>> findings) {
    final text = _content.text;
    final captionSpans = <(int, int)>[];
    for (final f in findings) {
      if ((f['source_origin']?.toString() ?? 'caption') != 'caption') continue;
      final s = int.tryParse(f['start_index']?.toString() ?? '');
      final e = int.tryParse(f['end_index']?.toString() ?? '');
      if (s != null && e != null && s >= 0 && e > s && e <= text.length) {
        captionSpans.add((s, e));
      }
    }
    if (captionSpans.isEmpty) return const SizedBox.shrink();
    captionSpans.sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final span in captionSpans) {
      if (span.$1 < cursor) continue;
      if (span.$1 > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, span.$1)));
      }
      spans.add(
        TextSpan(
          text: text.substring(span.$1, span.$2),
          style: TextStyle(
            color: AppTheme.danger,
            backgroundColor: AppTheme.dangerBg,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.danger,
          ),
        ),
      );
      cursor = span.$2;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text.rich(
        TextSpan(
          style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
          children: spans,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  List<Widget> _assetsAndSubmitChildren() {
    return [
      SectionHeading(
        title: 'Attached visual & document assets',
        caption: 'Supports TXT, MD, PDF & PNG/JPG/WEBP banners (OCR + palette + logo)',
        trailing: TextButton.icon(
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.upload_file_rounded, size: 16),
          label: const Text('Add'),
        ),
      ),
      const SizedBox(height: 8),
      if (_attachments.isEmpty)
        const InlineNotice(
          tone: Tone.neutral,
          icon: Icons.attach_file_rounded,
          title: 'No attachment yet',
          message:
              'Upload TXT, Markdown, text PDF, or PNG/JPG/WEBP marketing banners up to 5 MB for multimodal OCR, color palette, and logo verification.',
        )
      else
        ..._attachments.map(_attachmentCard),
      const SizedBox(height: 18),
      const SectionHeading(
        title: 'Inspection policy engine',
        caption: 'Applied server-side on every run',
      ),
      const SizedBox(height: 8),
      _policyRow(
        'Multimodal OCR & visual rules',
        'Extracts banner text (OCR), dominant hex palette (VIS-02), and legacy logos (VIS-05).',
      ),
      _policyRow(
        'Pricing, temporal & regulatory rules',
        'Evaluates active rule versions and verified facts at the selected check date.',
      ),
      _policyRow(
        'Conflict gate & grounding verification',
        'Abstains on internal policy conflicts and drops ungrounded findings.',
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(
                  _revision == null
                      ? 'Save draft'
                      : 'Save draft · r$_revision',
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 52,
        child: FilledButton(
          key: const ValueKey('run-check'),
          onPressed: _busy ? null : _check,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.teal,
            minimumSize: const Size(0, 52),
          ),
          child: _busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_rounded, size: 19),
                    SizedBox(width: 8),
                    Text('Run Brand Check'),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          'Runs against the live API · composite SHA-256 text + asset binding',
          style: AppTheme.monoLabel().copyWith(fontSize: 9),
        ),
      ),
    ];
  }

  Widget _attachmentCard(Map<String, dynamic> asset) {
    final isImage = asset['is_image'] == true;
    final bytes = asset['local_bytes'];
    final colors = (asset['dominant_colors'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    final ocrText = asset['extracted_text']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(10),
        radius: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isImage && bytes is Uint8List)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      bytes,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isImage ? Icons.image_outlined : Icons.description_outlined,
                      size: 19,
                      color: AppTheme.tealText,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset['name'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.labelLarge.copyWith(fontSize: 12.5),
                      ),
                      Text(
                        isImage
                            ? '${asset['width'] ?? '?'}x${asset['height'] ?? '?'} · OCR: ${asset['ocr_status'] ?? 'ready'}'
                            : 'Server-stored document',
                        style: AppTheme.monoLabel().copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove reference',
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _attachments.remove(asset));
                          _schedulePreflight(
                            delay: const Duration(milliseconds: 100),
                          );
                        },
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
            if (colors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: colors.take(4).map((c) {
                  final hex = c['hex']?.toString() ?? '';
                  final parsed = _parseHexColor(hex);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (parsed != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: parsed,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.borderStrong),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          '$hex (${c['coverage_pct'] ?? 0}%)',
                          style: AppTheme.monoLabel().copyWith(fontSize: 9),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            if (isImage && ocrText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'OCR: $ocrText',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.muted),
          const SizedBox(width: 4),
          Text(label, style: AppTheme.monoLabel()),
        ],
      ),
    );
  }

  Widget _stepStrip() {
    const labels = ['Details', 'Content', 'Assets', 'Review'];
    final current = _step;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= current ? AppTheme.teal : AppTheme.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      i < current
                          ? Icons.check_circle_rounded
                          : i == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 11,
                      color: i <= current ? AppTheme.teal : AppTheme.muted,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        labels[i].toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.monoLabel(
                          color: i <= current
                              ? AppTheme.tealText
                              : AppTheme.muted,
                        ).copyWith(fontSize: 8.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (i != labels.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _policyRow(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        radius: 14,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.mint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppTheme.tealText,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.labelLarge.copyWith(fontSize: 12.5),
                  ),
                  Text(subtitle, style: AppTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const StatusPill(label: 'On', tone: Tone.success, compact: true),
          ],
        ),
      ),
    );
  }
}
