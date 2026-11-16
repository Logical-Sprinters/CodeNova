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

  void _message(Object value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value.toString())));
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await BrandGuardApiService.saveDraft({
        'title': _title.text.trim().isEmpty
            ? 'Untitled draft'
            : _title.text.trim(),
        'brand_name': _brand.text.trim(),
        'content': _content.text,
        'attachments': _attachments,
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
      setState(
        () => _attachments.add({'id': result['id'], 'name': result['name']}),
      );
      final text = result['extracted_text']?.toString() ?? '';
      if (!mounted) return;
      final insert = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Document uploaded'),
          content: Text(
            'Extracted ${text.length} characters from ${result['name']}. Insert this text into the editor? Only the editor text is checked.',
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
      }
      _message('Save the draft to retain its attachment reference.');
    } catch (e) {
      _message(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_content.text.trim().isEmpty || _brand.text.trim().isEmpty) {
      _message('Enter a brand and nonempty content.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final exactText = _content.text;
    try {
      final result = await BrandGuardApiService.checkBrand(
        brandName: _brand.text.trim(),
        content: exactText,
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

  @override
  Widget build(BuildContext context) {
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
          children: [
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
                    child: const Icon(
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
                          '${_brand.text.trim()} · autosaved on the server once you press Draft',
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
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Brand',
                helperText: 'Acme ships starter rules. Reviewers can add another brand.',
                isDense: true,
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('check-content'),
              controller: _content,
              enabled: !_busy,
              minLines: 8,
              maxLines: 24,
              maxLength: 200000,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                hintText: 'Paste the exact copy that will be published. The check hashes this text exactly as written.',
                border: OutlineInputBorder(),
              ),
            ),
            Row(
              children: [
                _metaChip(Icons.notes_rounded, '$_wordCount words'),
                const SizedBox(width: 8),
                _metaChip(
                  Icons.text_fields_rounded,
                  '${_content.text.length} chars',
                ),
                const SizedBox(width: 8),
                _metaChip(
                  Icons.schedule_rounded,
                  '~${((_wordCount / 200) * 60).ceil()}s read',
                ),
              ],
            ),
            const SizedBox(height: 18),
            SectionHeading(
              title: 'Attached visual assets',
              caption: 'Stored privately, scoped to your identity',
              trailing: TextButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Add'),
              ),
            ),
            const SizedBox(height: 8),
            if (_attachments.isEmpty)
              InlineNotice(
                tone: Tone.neutral,
                icon: Icons.attach_file_rounded,
                title: 'No attachment yet',
                message: 'TXT, Markdown or text-based PDF up to 5 MB / 30 pages. Images and scanned PDFs need OCR, which this server does not run — only extracted text is checked.',
              )
            else
              ..._attachments.map(
                (asset) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(10),
                    radius: 14,
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppTheme.mint,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
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
                                style: AppTheme.labelLarge.copyWith(
                                  fontSize: 12.5,
                                ),
                              ),
                              Text(
                                'Server-stored document',
                                style: AppTheme.monoLabel().copyWith(
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove reference',
                          onPressed: _busy
                              ? null
                              : () =>
                                    setState(() => _attachments.remove(asset)),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            const SectionHeading(
              title: 'Inspection policy engine',
              caption: 'Applied server-side on every run',
            ),
            const SizedBox(height: 8),
            _policyRow(
              'Pricing & numeric claim rules',
              'Cross-checks prices, percentages and commitments against approved rules.',
            ),
            _policyRow(
              'Regulatory & compliance rules',
              'Flags absolute or restricted statements that need a disclaimer.',
            ),
            _policyRow(
              'Tone & voice rules',
              'Validates terminology and the shared brand voice.',
            ),
            const SizedBox(height: 8),
            Text(
              'These switches are informational: the API applies every active rule version. Rules cannot be disabled from the app.',
              style: AppTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            InlineNotice(
              tone: Tone.info,
              icon: Icons.manage_search_rounded,
              title: 'Deterministic rules, honest AI abstention',
              message: 'Checks use the current backend rules and reviewer-verified fact sources. If AI comparison is unavailable it abstains instead of guessing. A clean scan is not human approval.',
            ),
            const SizedBox(height: 18),
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
                'Runs against the live API · exact-text SHA-256 binding',
                style: AppTheme.monoLabel().copyWith(fontSize: 9),
              ),
            ),
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
              child: const Icon(
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
