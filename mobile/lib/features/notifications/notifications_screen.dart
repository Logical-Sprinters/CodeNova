import 'package:material_ui/material_ui.dart';

import '../../core/network/brandguard_api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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
      final data = await BrandGuardApiService.getJson('/api/v1/notifications');
      if (mounted) {
        setState(() {
          _items = (data['items'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _act(
    String method,
    String suffix, {
    Map<String, dynamic>? body,
  }) async {
    try {
      await BrandGuardApiService.request(
        method,
        '/api/v1/notifications$suffix',
        body: body,
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
      title: const Text('Notifications'),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'read') _act('PATCH', '/read-all');
            if (v == 'clear') _act('DELETE', '');
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'read', child: Text('Mark all read')),
            PopupMenuItem(value: 'clear', child: Text('Clear all')),
          ],
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Live in-app activity. Refresh to retrieve new backend notifications.',
          ),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (!_loading && _error == null && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No notifications yet.'),
            ),
          ..._items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: item['read'] == true
                    ? Colors.white
                    : const Color(0xFFEAF4EE),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  onTap: () =>
                      _act('PATCH', '/${item['id']}', body: {'read': true}),
                  leading: Icon(
                    item['read'] == true
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                    color: Colors.teal,
                  ),
                  title: Text(item['title'].toString()),
                  subtitle: Text('${item['body']}\n${item['created_at']}'),
                  trailing: IconButton(
                    onPressed: () => _act('DELETE', '/${item['id']}'),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
