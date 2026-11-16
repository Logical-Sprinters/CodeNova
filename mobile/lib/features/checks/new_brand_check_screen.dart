import 'package:material_ui/material_ui.dart';

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
          (e) => Map<String, dynamic>.from(e),
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
                ? Map<String, dynamic>.from(result['ai_verification'])
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_draftId == null ? 'New Brand Check' : 'Edit Saved Draft'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const Text(
          'Write • Check • Human review',
          style: TextStyle(
            color: Color(0xFF006B5E),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('draft-title'),
          controller: _title,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Draft title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('check-brand'),
          controller: _brand,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Brand',
            helperText:
                'Acme includes starter rules. Reviewers can add another brand.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('check-content'),
          controller: _content,
          enabled: !_busy,
          minLines: 10,
          maxLines: 24,
          maxLength: 200000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Content to check',
            alignLabelWithHint: true,
            hintText: 'Paste your exact content here...',
            border: OutlineInputBorder(),
          ),
        ),
        Text(
          '${_content.text.trim().isEmpty ? 0 : _content.text.trim().split(RegExp(r'\s+')).length} words · ${_content.text.length} characters',
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Private documents',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.attach_file),
              label: const Text('Upload'),
            ),
          ],
        ),
        const Text(
          'TXT, Markdown or text PDF • maximum 5 MB / 30 PDF pages. Images and scanned PDFs need OCR and are not supported. Attachments are stored privately; insert extracted text to check it.',
        ),
        ..._attachments.map(
          (asset) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(asset['name'].toString()),
            subtitle: const Text('Server-stored document'),
            trailing: IconButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _attachments.remove(asset)),
              tooltip: 'Remove reference',
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Checks use the current backend rules and eligible reviewer-verified fact sources. An AI comparison needs provider access; otherwise it explicitly abstains. A clean scan is not human approval.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const ValueKey('save-draft'),
          onPressed: _busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _revision == null
                ? 'Save Draft'
                : 'Save Draft · revision $_revision',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('run-check'),
          onPressed: _busy ? null : _check,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.shield_outlined),
          label: Padding(
            padding: const EdgeInsets.all(13),
            child: Text(_busy ? 'Please wait...' : 'Run Brand Check'),
          ),
        ),
      ],
    ),
  );
}
