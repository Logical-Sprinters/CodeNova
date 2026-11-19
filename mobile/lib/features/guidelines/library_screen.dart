import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../../core/network/document_picker.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.kind, required this.title});
  final String kind, title;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _brand = TextEditingController(text: 'Acme');
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _testingAi = false;
  Map<String, dynamic>? _aiProbeResult;
  String? _error;
  bool get _canManage => session.currentUser?.isReviewer ?? false;
  String get _base => '/api/v1/library/${widget.kind}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _brand.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson(
        '$_base?brand_name=${Uri.encodeQueryComponent(_brand.text.trim())}',
      );
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _message(Object message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));
    }
  }

  Future<void> _testAiVerification() async {
    if (_testingAi) return;
    setState(() => _testingAi = true);
    try {
      final res = await BrandGuardApiService.testAiConnection();
      if (!mounted) return;
      setState(() {
        _aiProbeResult = res;
        _testingAi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _testingAi = false);
      _message(e);
    }
  }

  Future<void> _quickVerifyFact(Map<String, dynamic> item) async {
    try {
      final body = <String, dynamic>{
        'title': item['title']?.toString() ?? 'Verified fact',
        'brand_name': item['brand_name']?.toString() ?? _brand.text.trim(),
        'content': item['content']?.toString() ?? '',
        'source_url': item['source_url']?.toString() ?? '',
        'description': item['description']?.toString() ?? '',
        'enabled': true,
        'verified': true,
        if ((item['canonical_value']?.toString() ?? '').isNotEmpty)
          'canonical_value': item['canonical_value'].toString(),
        if ((item['effective_from']?.toString() ?? '').isNotEmpty)
          'effective_from': item['effective_from'].toString(),
        if ((item['expires_at']?.toString() ?? '').isNotEmpty)
          'expires_at': item['expires_at'].toString(),
      };
      await BrandGuardApiService.request(
        'PUT',
        '$_base/${Uri.encodeComponent(item['id'].toString())}',
        body: body,
      );
      _message('Source verified and enabled for AI retrieval.');
      await _load();
    } catch (e) {
      _message(e);
    }
  }

  Color? _parseHexColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final val = int.tryParse(cleaned, radix: 16);
    if (val == null) return null;
    return Color(0xFF000000 | val);
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final fields = <String, String>{
      'title': 'Title',
      if (widget.kind == 'rules') ...{
        'pattern': 'Regex pattern (enforced by API)',
        'description': 'Finding message',
        'suggestion': 'Suggested action',
        'replacement': 'Replacement (optional)',
        'version': 'Version (e.g. 1.0.0)',
        'effective_from': 'Effective from (ISO-8601, optional)',
        'expires_at': 'Expires at (ISO-8601, optional)',
      },
      if (widget.kind == 'facts') ...{
        'content': 'Actual source text',
        'source_url': 'Source URL (optional)',
        'canonical_value': 'Canonical numeric/claim value (optional)',
        'effective_from': 'Effective from (ISO-8601, optional)',
        'expires_at': 'Expires at (ISO-8601, optional)',
      },
      if (widget.kind == 'guidelines') ...{
        'description': 'Guideline',
        'category': 'Category',
      },
    };
    final controls = {
      for (final key in fields.keys)
        key: TextEditingController(
          text: key == 'version'
              ? (item?[key]?.toString() ?? '1.0.0')
              : (item?[key]?.toString() ?? ''),
        ),
    };
    final hexCtrl = TextEditingController(
      text: ((item?['allowed_hex_colors'] as List? ?? [])
          .map((e) => e.toString())
          .join(', ')),
    );

    var ruleType = item?['rule_type']?.toString() ?? 'regex';
    final selectedChannels = <String>{
      ...((item?['channels'] as List? ?? ['all']).map((e) => e.toString())),
    };
    if (selectedChannels.isEmpty) selectedChannels.add('all');

    var verified = item?['verified'] == true;
    var enabled = item?['enabled'] != false;
    var busy = false;
    String? error;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(
            item == null ? 'Add ${widget.kind}' : 'Edit ${widget.kind}',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Brand: ${_brand.text}'),
                  if (widget.kind == 'rules') ...[
                    const SizedBox(height: 10),
                    Text('RULE TYPE', style: AppTheme.monoLabel()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        'regex',
                        'visual_palette',
                        'visual_logo',
                        'fact_claim',
                      ].map((rt) {
                        final active = ruleType == rt;
                        return GestureDetector(
                          onTap: () => update(() => ruleType = rt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppTheme.mint
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: active ? AppTheme.teal : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              rt,
                              style: AppTheme.monoLabel(
                                color: active
                                    ? AppTheme.tealText
                                    : AppTheme.ink,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Text('CHANNELS', style: AppTheme.monoLabel()),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['all', 'instagram', 'linkedin', 'email', 'web']
                          .map((ch) {
                        final active = selectedChannels.contains(ch);
                        return GestureDetector(
                          onTap: () => update(() {
                            if (active && selectedChannels.length > 1) {
                              selectedChannels.remove(ch);
                            } else {
                              selectedChannels.add(ch);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppTheme.mint
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: active ? AppTheme.teal : AppTheme.border,
                              ),
                            ),
                            child: Text(
                              ch.toUpperCase(),
                              style: AppTheme.monoLabel(
                                color: active
                                    ? AppTheme.tealText
                                    : AppTheme.ink,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  ...fields.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: controls[entry.key],
                        maxLines: entry.key == 'content'
                            ? 6
                            : entry.key == 'description'
                            ? 3
                            : 1,
                        decoration: InputDecoration(
                          labelText: entry.value,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  if (widget.kind == 'rules' && ruleType == 'visual_palette')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: hexCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Allowed hex colors (comma-separated)',
                          hintText: '#0F172A, #FFFFFF, #10B981',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Checkbox(
                        value: enabled,
                        onChanged: (v) => update(() => enabled = v ?? true),
                      ),
                      const Expanded(child: Text('Enabled')),
                    ],
                  ),
                  if (widget.kind == 'facts')
                    Row(
                      children: [
                        Checkbox(
                          value: verified,
                          onChanged: (v) => update(() => verified = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'I verified this source. Allow it in AI retrieval.',
                          ),
                        ),
                      ],
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
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
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final body = <String, dynamic>{
                          for (final e in controls.entries)
                            e.key: e.value.text.trim(),
                          'brand_name': _brand.text.trim(),
                          'enabled': enabled,
                          'verified': verified,
                          'severity': item?['severity'] ?? 'review',
                        };
                        if (body['replacement'] == '') {
                          body['replacement'] = null;
                        }
                        if (body['effective_from'] == '') {
                          body.remove('effective_from');
                        }
                        if (body['expires_at'] == '') {
                          body.remove('expires_at');
                        }
                        if (body['canonical_value'] == '') {
                          body.remove('canonical_value');
                        }
                        if (widget.kind == 'rules') {
                          body['rule_type'] = ruleType;
                          body['channels'] = selectedChannels.toList();
                          if (ruleType == 'visual_palette') {
                            body['allowed_hex_colors'] = hexCtrl.text
                                .split(',')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList();
                          }
                        }
                        await BrandGuardApiService.request(
                          item == null ? 'POST' : 'PUT',
                          item == null
                              ? _base
                              : '$_base/${Uri.encodeComponent(item['id'].toString())}',
                          body: body,
                        );
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } catch (e) {
                        if (dialog.mounted) {
                          update(() {
                            busy = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    hexCtrl.dispose();
    for (final controller in controls.values) {
      controller.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text(item['title']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await BrandGuardApiService.request(
        'DELETE',
        '$_base/${Uri.encodeComponent(item['id'].toString())}?brand_name=${Uri.encodeQueryComponent(_brand.text)}',
      );
      await _load();
    } catch (e) {
      _message(e);
    }
  }

  Future<void> _upload() async {
    try {
      final data = await pickAndUploadDocument(
        asFact: true,
        brandName: _brand.text.trim(),
      );
      if (data != null) {
        _message(
          'Uploaded as unverified source. Review its text, then enable verification.',
        );
        await _load();
      }
    } catch (e) {
      _message(e);
    }
  }

  Future<void> _uploadLogoTemplate({String? defaultRuleId}) async {
    final fallbackRule = _items.firstWhere(
      (r) => r['rule_type']?.toString() == 'visual_logo',
      orElse: () => {'id': 'VIS-05'},
    );
    final ruleCtrl = TextEditingController(
      text: defaultRuleId ?? fallbackRule['id']?.toString() ?? 'VIS-05',
    );
    final labelCtrl = TextEditingController(text: 'Deprecated 2024 Logo');
    final route = DialogRoute<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload deprecated logo template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ruleCtrl,
              decoration: const InputDecoration(
                labelText: 'Visual logo rule ID',
                hintText: 'e.g. VIS-05',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Template label',
                hintText: 'e.g. Old 2021 Wordmark',
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
            onPressed: () => Navigator.pop(
              ctx,
              (ruleCtrl.text.trim(), labelCtrl.text.trim()),
            ),
            child: const Text('Choose image'),
          ),
        ],
      ),
    );
    try {
      final result = await Navigator.of(context).push(route);
      if (result == null || result.$1.isEmpty || result.$2.isEmpty) return;
      final res = await pickAndUploadLogoTemplate(
        ruleId: result.$1,
        brandName: _brand.text.trim(),
        label: result.$2,
      );
      if (res != null && mounted) {
        _message(
          'Logo template "${result.$2}" attached to ${result.$1} (${res['total_templates'] ?? 1} template(s)).',
        );
        await _load();
      }
    } catch (e) {
      _message(e);
    } finally {
      await route.completed;
      ruleCtrl.dispose();
      labelCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final isRules = widget.kind == 'rules';
    final isFacts = widget.kind == 'facts';
    final readOnly = !_canManage;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (_canManage && isRules)
            IconButton(
              onPressed: () => _uploadLogoTemplate(),
              tooltip: 'Upload deprecated logo template',
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (_canManage && isFacts)
            IconButton(
              onPressed: _upload,
              tooltip: 'Upload source document',
              icon: const Icon(Icons.upload_file_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                isRules
                    ? 'New rule'
                    : isFacts
                    ? 'New source'
                    : 'New guideline',
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              PageIntro(
                eyebrow: isRules
                    ? 'DETERMINISTIC GROUNDING'
                    : isFacts
                    ? 'EVIDENCE REPOSITORY'
                    : 'SHARED GUIDANCE',
                eyebrowTone: isRules
                    ? Tone.navy
                    : isFacts
                    ? Tone.info
                    : Tone.success,
                title: widget.title,
                subtitle: isRules
                    ? 'Versioned text, channel, temporal & visual rules executed on every check.'
                    : isFacts
                    ? 'Upload private documents and mark only truly verified evidence as eligible.'
                    : 'Descriptive brand guidance. Enforceable patterns belong in Rules.',
              ),
              const SizedBox(height: 14),
              SurfaceCard(
                padding: const EdgeInsets.all(12),
                radius: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _brand,
                        onSubmitted: (_) => _load(),
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Brand',
                          prefixIcon: Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _load,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.navy,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Load'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (readOnly)
                InlineNotice(
                  tone: Tone.navy,
                  icon: Icons.visibility_outlined,
                  title: 'Read-only: reviewer-managed',
                  message:
                      'A reviewer manages the shared brand library. You can inspect every entry used by checks.',
                ),
              if (readOnly) const SizedBox(height: 10),
              InlineNotice(
                tone: isFacts ? Tone.warning : Tone.info,
                title: isRules
                    ? 'Editing a rule invalidates old approvals'
                    : isFacts
                    ? 'A URL alone is not factual verification'
                    : 'Guidance is descriptive, not enforced',
                message: isRules
                    ? 'Rule changes bump the rules version, so previous approvals are reported as out-of-date by the receipt endpoint.'
                    : isFacts
                    ? 'Only enabled, reviewer-verified source text is eligible for retrieval. Unverified uploads are excluded.'
                    : 'Guidance helps humans decide. Only Rules change inspection output.',
              ),
              if (_canManage && isFacts) ...[
                const SizedBox(height: 10),
                SurfaceCard(
                  radius: 16,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(
                            label: _aiProbeResult == null
                                ? 'AI Probe Ready'
                                : (_aiProbeResult!['live_ok'] == true
                                    ? 'AI Active (${_aiProbeResult!['provider'] ?? ''})'
                                    : 'AI Disabled / Check Key'),
                            tone: _aiProbeResult == null
                                ? Tone.navy
                                : (_aiProbeResult!['live_ok'] == true
                                    ? Tone.success
                                    : Tone.warning),
                            compact: true,
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('test-ai-btn'),
                            onPressed: _testingAi ? null : _testAiVerification,
                            icon: _testingAi
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_awesome_outlined,
                                    size: 16,
                                  ),
                            label: Text(
                              _testingAi ? 'Testing...' : 'Test AI verification',
                            ),
                          ),
                        ],
                      ),
                      if (_aiProbeResult != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            if ((_aiProbeResult!['model']?.toString() ?? '')
                                .isNotEmpty)
                              'Model: ${_aiProbeResult!['model']}',
                            if ((_aiProbeResult!['message']?.toString() ?? '')
                                .isNotEmpty)
                              _aiProbeResult!['message'].toString(),
                          ].join(' · '),
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SectionHeading(
                title: 'Library entries',
                caption:
                    '${_items.length} record${_items.length == 1 ? '' : 's'} for ${_brand.text.trim()}',
              ),
              const SizedBox(height: 10),
              if (_loading)
                const LoadingBlock()
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_items.isEmpty)
                EmptyStateCard(
                  title: 'No entries yet',
                  message: _canManage
                      ? 'Add the first entry with the button below.'
                      : 'A reviewer can add the first entry for this brand.',
                  icon: isRules
                      ? Icons.rule_rounded
                      : isFacts
                      ? Icons.fact_check_outlined
                      : Icons.menu_book_outlined,
                )
              else
                ..._items.map((item) => _entryCard(item, isRules, isFacts)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> item, bool isRules, bool isFacts) {
    final enabled = item['enabled'] != false;
    final verified = item['verified'] == true;
    final tone = !enabled
        ? Tone.neutral
        : isFacts
        ? (verified ? Tone.success : Tone.warning)
        : Tone.success;
    final channels = (item['channels'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final hexes = (item['allowed_hex_colors'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final logos = (item['deprecated_logo_hashes'] as List? ?? []);
    final effFrom = item['effective_from']?.toString();
    final expiresAt = item['expires_at']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['title']?.toString() ?? 'Untitled',
                    style: AppTheme.labelLarge.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                StatusPill(
                  label: !enabled
                      ? 'Disabled'
                      : isFacts
                      ? (verified ? 'Verified' : 'Unverified')
                      : 'Active',
                  tone: tone,
                  compact: true,
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: AppTheme.muted,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') _edit(item);
                      if (value == 'logo') {
                        _uploadLogoTemplate(
                          defaultRuleId: item['id']?.toString(),
                        );
                      }
                      if (value == 'delete') _delete(item);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (isRules &&
                          item['rule_type']?.toString() == 'visual_logo')
                        const PopupMenuItem(
                          value: 'logo',
                          child: Text('Upload deprecated logo'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),
            if (isRules || isFacts || item['category'] != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (item['version'] != null)
                    StatusPill(
                      label: 'v${item['version']}',
                      tone: Tone.navy,
                      compact: true,
                    ),
                  if (item['rule_type'] != null)
                    StatusPill(
                      label: item['rule_type'].toString(),
                      tone: Tone.info,
                      compact: true,
                    ),
                  if (logos.isNotEmpty)
                    StatusPill(
                      label: '${logos.length} logo template(s)',
                      tone: Tone.warning,
                      compact: true,
                    ),
                  if (item['category'] != null)
                    StatusPill(
                      label: item['category'].toString(),
                      tone: Tone.info,
                      compact: true,
                    ),
                  if (item['severity'] != null)
                    StatusPill(
                      label: item['severity'].toString(),
                      tone: Tone.warning,
                      compact: true,
                    ),
                  for (final ch in channels)
                    StatusPill(label: ch, tone: Tone.neutral, compact: true),
                ],
              ),
            ],
            if (effFrom != null || expiresAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Effective: ${effFrom ?? 'always'} -> ${expiresAt ?? 'ongoing'}',
                style: AppTheme.monoLabel(color: AppTheme.tealText),
              ),
            ],
            if (hexes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: hexes.map((h) {
                  final c = _parseHexColor(h);
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
                        if (c != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.borderStrong),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(h, style: AppTheme.monoLabel()),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            if (isRules &&
                item['pattern'] != null &&
                item['pattern'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SelectableText(
                  item['pattern'].toString(),
                  style: AppTheme.monoLabel(color: AppTheme.navy)
                      .copyWith(fontSize: 11),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              (item['description'] ?? item['content'] ?? '').toString(),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.ink,
                height: 1.45,
              ),
            ),
            if (item['canonical_value'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Canonical claim value: ${item['canonical_value']}',
                style: AppTheme.monoLabel(color: AppTheme.tealText),
              ),
            ],
            if (item['source_url'] != null &&
                item['source_url'].toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item['source_url'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.monoLabel(color: AppTheme.info),
              ),
            ],
            if (isFacts) ...[
              const SizedBox(height: 8),
              Text(
                verified
                    ? 'Reviewer verified · eligible as citation evidence'
                    : 'Unverified · excluded from retrieval and citations',
                style: AppTheme.monoLabel(
                  color: verified ? AppTheme.success : AppTheme.warning,
                ),
              ),
              if (_canManage && !verified && enabled) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _quickVerifyFact(item),
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Verify source for AI'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
