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

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final fields = <String, String>{
      'title': 'Title',
      if (widget.kind == 'rules') ...{
        'pattern': 'Regex pattern (enforced by API)',
        'description': 'Finding message',
        'suggestion': 'Suggested action',
        'replacement': 'Replacement (optional)',
      },
      if (widget.kind == 'facts') ...{
        'content': 'Actual source text',
        'source_url': 'Source URL (optional)',
      },
      if (widget.kind == 'guidelines') ...{
        'description': 'Guideline',
        'category': 'Category',
      },
    };
    final controls = {
      for (final key in fields.keys)
        key: TextEditingController(text: item?[key]?.toString() ?? ''),
    };
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
                children: [
                  Text('Brand: ${_brand.text}'),
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

  @override
  Widget build(BuildContext context) {
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
                    ? 'Versioned regex rules executed by the backend on every check.'
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
                  message: 'A reviewer manages the shared brand library. You can inspect every entry used by checks.',
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
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: AppTheme.muted,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') _edit(item);
                      if (value == 'delete') _delete(item);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            if (item['category'] != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
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
                ],
              ),
            ],
            if (isRules && item['pattern'] != null) ...[
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
            ],
          ],
        ),
      ),
    );
  }
}
