import 'package:material_ui/material_ui.dart';

import '../../core/network/brandguard_api_service.dart';
import '../checks/new_brand_check_screen.dart';

class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});
  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BrandGuardApiService.getJson('/api/v1/drafts');
      if (mounted) {
        setState(() {
          _items = (data['items'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _open([Map<String, dynamic>? item]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewBrandCheckScreen(draft: item)),
    );
    await _load();
  }

  Future<void> _delete(String id) async {
    try {
      await BrandGuardApiService.request(
        'DELETE',
        '/api/v1/drafts/${Uri.encodeComponent(id)}',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved Drafts'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _open(),
      child: const Icon(Icons.add),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (!_loading && _items.isEmpty && _error == null)
            const Text(
              'No saved drafts. Save one from the brand-check editor.',
            ),
          ..._items.map(
            (item) => Material(
              color: Colors.white,
              child: ListTile(
                onTap: () => _open(item),
                title: Text(item['title']?.toString() ?? 'Draft'),
                subtitle: Text(
                  '${item['brand_name']} · revision ${item['revision']}\n${item['updated_at']}',
                ),
                trailing: IconButton(
                  onPressed: () => _delete(item['id'].toString()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
