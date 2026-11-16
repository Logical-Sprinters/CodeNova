import 'package:material_ui/material_ui.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          onPressed: _load,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
        if (_canManage && widget.kind == 'facts')
          IconButton(
            onPressed: _upload,
            tooltip: 'Upload source document',
            icon: const Icon(Icons.upload_file),
          ),
      ],
    ),
    floatingActionButton: _canManage
        ? FloatingActionButton(
            onPressed: () => _edit(),
            child: const Icon(Icons.add),
          )
        : null,
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 90),
        children: [
          TextField(
            controller: _brand,
            decoration: InputDecoration(
              labelText: 'Brand',
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          Text(
            widget.kind == 'rules'
                ? 'These versioned regex rules run in the backend. Changing one invalidates old-rules approvals.'
                : widget.kind == 'facts'
                ? 'Only enabled, reviewer-verified source text is eligible for retrieval. A URL alone is not factual verification.'
                : 'Shared descriptive guidance. Enforceable patterns belong in Rules.',
          ),
          const SizedBox(height: 12),
          if (!_canManage)
            const Text(
              'Read-only: a reviewer manages the shared brand library.',
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (!_loading && _error == null && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No items yet. A reviewer can add the first one.'),
            ),
          ..._items.map(
            (item) => Card(
              margin: const EdgeInsets.symmetric(vertical: 7),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['title']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (_canManage)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _edit(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (widget.kind == 'rules')
                      SelectableText('Pattern: ${item['pattern']}'),
                    Text(
                      (item['description'] ?? item['content'] ?? '').toString(),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.kind == 'facts')
                      Text(
                        item['verified'] == true
                            ? 'Reviewer verified'
                            : 'Unverified — excluded from AI',
                        style: TextStyle(
                          color: item['verified'] == true
                              ? Colors.teal
                              : Colors.deepOrange,
                        ),
                      ),
                    if (item['enabled'] == false) const Text('Disabled'),
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
