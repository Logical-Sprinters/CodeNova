import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color navy = Color(0xFF142C3B);
  static const Color darkNavy = Color(0xFF001725);
  static const Color teal = Color(0xFF006B5E);
  static const Color background = Color(0xFFF7F8F6);
  static const Color border = Color(0xFFE5EAE7);
  static const Color secondary = Color(0xFF73787C);
  static const String storageKey = 'brandguard_notifications_v2';

  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;

  List<Map<String, dynamic>> _defaults() => [
    {'id': 'n1', 'title': 'Review pending',
      'body': 'ApexShield Product Announcement is awaiting authorised review.',
      'time': '10 min ago', 'type': 'review', 'read': false},
    {'id': 'n2', 'title': 'Changes requested',
      'body': 'Changes were requested for a submitted content item.',
      'time': '1 hour ago', 'type': 'decision', 'read': false},
    {'id': 'n3', 'title': 'Guideline reminder',
      'body': 'Check that the latest brand guidelines are applied to new content.',
      'time': 'Yesterday', 'type': 'guideline', 'read': true},
    {'id': 'n4', 'title': 'Fact source added',
      'body': 'A new reference source was added to the fact source library.',
      'time': 'Yesterday', 'type': 'source', 'read': true},
  ];

  TextStyle _style({double size = 13, FontWeight weight = FontWeight.w400,
    Color color = darkNavy}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, color: color);

  int get unreadCount => notifications.where((n) => n['read'] == false).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved == null) {
      notifications = _defaults();
      await _save();
    } else {
      try {
        final decoded = jsonDecode(saved) as List;
        notifications = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        notifications = _defaults();
        await _save();
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(notifications));
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final item in notifications) {
        item['read'] = true;
      }
    });
    await _save();
  }

  Future<void> _markRead(int index) async {
    setState(() => notifications[index]['read'] = true);
    await _save();
  }

  Future<void> _delete(int index) async {
    setState(() => notifications.removeAt(index));
    await _save();
  }

  Future<void> _clearAll() async {
    setState(notifications.clear);
    await _save();
  }

  IconData _icon(String type) {
    switch (type) {
      case 'review': return Icons.rate_review_rounded;
      case 'decision': return Icons.rule_rounded;
      case 'guideline': return Icons.menu_book_rounded;
      default: return Icons.source_rounded;
    }
  }

  Color _tint(String type) {
    switch (type) {
      case 'review': return const Color(0xFFE8F6FF);
      case 'decision': return const Color(0xFFFBF4E8);
      case 'guideline': return const Color(0xFFEAF4EE);
      default: return const Color(0xFFDDE8EF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: darkNavy,
        title: Text('Notifications',
          style: _style(size: 17, weight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: isLoading ? null : _markAllRead,
            child: Text('Mark all read',
              style: _style(size: 10, weight: FontWeight.w800, color: teal)),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _confirmClear();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear all notifications')),
            ],
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: navy, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.notifications_active_rounded,
                      color: Color(0xFF81F7E1), size: 30),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$unreadCount unread notifications',
                          style: _style(size: 14, weight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text('Updates about reviews, guidelines and sources.',
                          style: _style(size: 10, color: Colors.white70)),
                      ],
                    )),
                  ]),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Text('Recent updates', style: _style(size: 15, weight: FontWeight.w800)),
                  const Spacer(),
                  Text('${notifications.length} total',
                    style: _style(size: 10, color: secondary)),
                ]),
                const SizedBox(height: 10),
                if (notifications.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: border)),
                    child: Column(children: [
                      const Icon(Icons.notifications_off_outlined,
                        size: 34, color: secondary),
                      const SizedBox(height: 9),
                      Text('You are all caught up',
                        style: _style(size: 13, weight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('New activity will appear here.',
                        style: _style(size: 10, color: secondary)),
                    ]),
                  )
                else
                  ...notifications.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final read = item['read'] == true;
                    final type = item['type'] as String;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: read ? Colors.white : const Color(0xFFF0F8F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border)),
                      child: ListTile(
                        onTap: () => _markRead(index),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(color: _tint(type),
                            borderRadius: BorderRadius.circular(12)),
                          child: Icon(_icon(type), color: teal, size: 21),
                        ),
                        title: Row(children: [
                          Expanded(child: Text(item['title'] as String,
                            style: _style(size: 12, weight: FontWeight.w800))),
                          if (!read) Container(width: 7, height: 7,
                            decoration: const BoxDecoration(color: teal, shape: BoxShape.circle)),
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(item['body'] as String,
                              style: _style(size: 10, color: secondary)),
                            const SizedBox(height: 5),
                            Text(item['time'] as String,
                              style: _style(size: 9, color: secondary)),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'read') _markRead(index);
                            if (value == 'delete') _delete(index);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'read', child: Text('Mark as read')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear notifications?'),
        content: const Text('This removes all demo notifications from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) await _clearAll();
  }
}
