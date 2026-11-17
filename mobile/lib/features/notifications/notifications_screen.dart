import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
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
              .map((e) => Map<String, dynamic>.from(e as Map))
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

  int get _unread => _items.where((i) => i['read'] != true).length;

  String _stamp(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    final local = parsed.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} · ${two(local.hour)}:${two(local.minute)}';
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
        title: const Text('Notifications'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
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
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
            children: [
              PageIntro(
                eyebrow: _unread > 0 ? '$_unread UNREAD' : 'INBOX CLEAR',
                eyebrowTone: _unread > 0 ? Tone.info : Tone.success,
                title: 'Activity feed',
                subtitle: 'Live in-app events recorded by the backend. Pull to refresh for new events.',
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LoadingBlock(label: 'Loading notifications…')
              else if (_error != null)
                ErrorBlock(message: _error!, onRetry: _load)
              else if (_items.isEmpty)
                const EmptyStateCard(
                  title: 'No notifications yet',
                  message: 'Review decisions and submission events appear here as soon as the server records them.',
                  icon: Icons.notifications_none_rounded,
                )
              else
                ..._items.map((item) {
                  final unread = item['read'] != true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      radius: 16,
                      onTap: () =>
                          _act('PATCH', '/${item['id']}', body: {'read': true}),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: unread
                                  ? AppTheme.infoBg
                                  : AppTheme.neutralBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              unread
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              size: 17,
                              color: unread ? AppTheme.info : AppTheme.muted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['title'].toString(),
                                  style: AppTheme.labelLarge.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item['body'].toString(),
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _stamp(item['created_at']),
                                  style: AppTheme.monoLabel().copyWith(
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Delete notification',
                            onPressed: () => _act('DELETE', '/${item['id']}'),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
