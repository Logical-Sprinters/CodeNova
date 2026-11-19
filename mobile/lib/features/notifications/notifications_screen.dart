import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../app/ui/app_widgets.dart';
import '../../core/network/brandguard_api_service.dart';
import '../reviews/review_queue_screen.dart';

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

  List<Map<String, dynamic>> get _unseenItems =>
      _items.where((i) => i['read'] != true).toList();

  List<Map<String, dynamic>> get _seenItems =>
      _items.where((i) => i['read'] == true).toList();

  Future<void> _openNotification(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    final unread = item['read'] != true;
    final checkId = item['check_id']?.toString() ?? '';
    final isChangesReq =
        item['title']?.toString().toLowerCase().contains('changes') ?? false;

    if (unread && id.isNotEmpty) {
      setState(() {
        item['read'] = true;
      });
      await _act('PATCH', '/$id', body: {'read': true});
    }

    if (checkId.isNotEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewQueueScreen(
            initialTab: isChangesReq ? 'Changes Requested' : 'All',
            initialCheckId: checkId,
          ),
        ),
      );
      if (mounted) await _load();
    }
  }

  Widget _notificationCard(Map<String, dynamic> item) {
    final unread = item['read'] != true;
    final checkId = item['check_id']?.toString() ?? '';
    final isChangesReq =
        item['title']?.toString().toLowerCase().contains('changes') ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        radius: 16,
        borderColor: unread
            ? AppTheme.info.withValues(alpha: 0.45)
            : AppTheme.border,
        color: unread ? AppTheme.card : AppTheme.background,
        onTap: () => _openNotification(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: unread ? AppTheme.infoBg : AppTheme.neutralBg,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['title'].toString(),
                          style: AppTheme.labelLarge.copyWith(
                            fontSize: 13,
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (unread)
                        const StatusPill(
                          label: 'Unseen',
                          tone: Tone.info,
                          compact: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item['body'].toString(),
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stamp(item['created_at']),
                    style: AppTheme.monoLabel().copyWith(fontSize: 9),
                  ),
                  if (checkId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _openNotification(item),
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        label: Text(
                          isChangesReq ? 'Open & edit check' : 'Open check',
                        ),
                      ),
                    ),
                  ],
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
  }

  String _stamp(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    final local = parsed.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)} ${months[local.month - 1]} ${local.year} · $hour12:${two(local.minute)} $amPm';
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
              else ...[
                SectionHeading(
                  title: 'Unseen',
                  caption: _unseenItems.isEmpty
                      ? 'All notifications viewed'
                      : '${_unseenItems.length} waiting — tap to open and mark seen',
                ),
                const SizedBox(height: 8),
                if (_unseenItems.isEmpty)
                  const EmptyStateCard(
                    title: 'No unseen notifications',
                    message: 'Opened notifications automatically move to Seen below.',
                    icon: Icons.mark_email_read_outlined,
                  )
                else
                  ..._unseenItems.map(_notificationCard),
                if (_seenItems.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  SectionHeading(
                    title: 'Seen',
                    caption: '${_seenItems.length} viewed',
                  ),
                  const SizedBox(height: 8),
                  ..._seenItems.map(_notificationCard),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
