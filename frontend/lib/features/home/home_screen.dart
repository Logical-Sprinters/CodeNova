import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../findings/findings_screen.dart';

/// What exists, and in what state. Every figure on this screen is an API field.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<ContentSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ContentSummary>> _load() async {
    final dynamic data = await Api.get('/content');
    return (data as List<dynamic>)
        .map((dynamic e) => ContentSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<ContentSummary>>(
      future: _future,
      isEmpty: (List<ContentSummary> d) => d.isEmpty,
      emptyMessage: 'No copy yet.\nUse "New check" to submit the first item.',
      onRetry: _reload,
      builder: (BuildContext context, List<ContentSummary> items) {
        return RefreshIndicator(
          color: Bg.secondary,
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int i) {
              if (i == 0) {
                return Text(
                  'Signed in as ${session.user?.name} (${session.user?.role})',
                  style: const TextStyle(fontSize: 12, color: Bg.unsupported),
                );
              }
              return _ContentCard(item: items[i - 1], onChanged: _reload);
            },
          ),
        );
      },
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.item, required this.onChanged});

  final ContentSummary item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final String state = item.approvalState ?? 'DRAFT';
    final Color colour = StatusStyle.colour(state);

    return Material(
      color: Bg.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FindingsScreen(contentId: item.id),
            ),
          );
          onChanged();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Bg.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  StatusChip(item.channel, colour: Bg.primary),
                  const SizedBox(width: 8),
                  StatusChip(StatusStyle.label(state), colour: colour,
                      filled: state == 'APPROVED'),
                  const Spacer(),
                  Text(
                    'v${item.versionNumber}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.title == null ? item.text : '${item.title} — ${item.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.45, color: Bg.ink),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  HashLabel(item.hash),
                  const Spacer(),
                  if (item.blocking > 0)
                    Text(
                      '${item.blocking} blocking · ${item.total} findings',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Bg.confirmed,
                      ),
                    )
                  else
                    Text(
                      item.total == 0 ? 'no findings' : '${item.total} findings, none blocking',
                      style: const TextStyle(fontSize: 12, color: Bg.unsupported),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
