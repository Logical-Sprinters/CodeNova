import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';
import '../findings/findings_screen.dart';

/// What is waiting for a person.
///
/// Items with an unresolved confirmed match are deliberately absent: the first
/// move there is to fix the copy, not to queue it. A queue you cannot act on is
/// worse than no queue.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late Future<List<QueueItem>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<QueueItem>> _load() async {
    final dynamic data = await Api.get('/queue');
    return (data as List<dynamic>)
        .map((dynamic e) => QueueItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _approve(QueueItem item) async {
    setState(() => _busy = true);
    try {
      await Api.post('/content/${item.id}/approve');
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Bg.approved,
          content: Text(
            'Approved v${item.versionNumber} — bound to its hash, '
            '${item.advisory} finding(s) acknowledged.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Bg.confirmed, content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<QueueItem>>(
      future: _future,
      isEmpty: (List<QueueItem> d) => d.isEmpty,
      emptyMessage: 'Nothing is waiting for review.\n\n'
          'Items with a confirmed rule match never appear here — they have to be '
          'repaired first. That is the point of the queue.',
      onRetry: _reload,
      builder: (BuildContext context, List<QueueItem> items) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int i) {
            final QueueItem item = items[i];
            final String state = item.approvalState ?? 'DRAFT';
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Bg.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Bg.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      StatusChip('v${item.versionNumber}', colour: Bg.primary),
                      const SizedBox(width: 8),
                      StatusChip(StatusStyle.label(state), colour: Bg.unsupported),
                      const Spacer(),
                      Text(
                        item.creator,
                        style: const TextStyle(fontSize: 11, color: Bg.unsupported),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.advisory == 0
                        ? 'No findings. Nothing to acknowledge.'
                        : '${item.advisory} finding(s) to acknowledge — none of them '
                            'block approval.',
                    style: const TextStyle(fontSize: 11.5, color: Bg.unsupported),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FindingsScreen(contentId: item.id),
                              ),
                            );
                            _reload();
                          },
                          child: const Text('Open'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: (!session.canApprove || _busy)
                              ? null
                              : () => _approve(item),
                          child: Text(
                            session.canApprove
                                ? 'Approve v${item.versionNumber}'
                                : 'Reviewer only',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
