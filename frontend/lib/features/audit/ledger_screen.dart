import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Append-only. A USER row means a person acted; a SYSTEM row means the database
/// did, on its own, because an invariant required it. The void rows are the point.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late Future<List<LedgerEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LedgerEntry>> _load() async {
    final dynamic data = await Api.get('/ledger');
    return (data as List<dynamic>)
        .map((dynamic e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  IconData _icon(String action) {
    switch (action) {
      case 'approved':
        return Icons.check;
      case 'voided':
        return Icons.link_off;
      case 'edited':
        return Icons.edit_outlined;
      case 'overridden':
        return Icons.gavel_outlined;
      case 'checked':
        return Icons.rule;
      default:
        return Icons.upload_file_outlined;
    }
  }

  Color _colour(String action) {
    switch (action) {
      case 'approved':
        return Bg.approved;
      case 'voided':
        return Bg.voided;
      case 'overridden':
        return Bg.human;
      default:
        return Bg.primary;
    }
  }

  String _headline(LedgerEntry entry) {
    switch (entry.action) {
      case 'voided':
        return 'Approval automatically voided';
      case 'checked':
        return 'Check run completed — ${entry.details['findings'] ?? 0} findings';
      case 'approved':
        return 'Approved by ${entry.actor ?? 'a reviewer'}';
      case 'edited':
        return 'New version created${entry.actor == null ? '' : ' by ${entry.actor}'}';
      case 'overridden':
        return 'Finding overridden${entry.actor == null ? '' : ' by ${entry.actor}'}';
      case 'submitted':
        return 'Copy submitted${entry.actor == null ? '' : ' by ${entry.actor}'}';
      default:
        return entry.action;
    }
  }

  String _detail(LedgerEntry entry) {
    final Map<String, dynamic> d = entry.details;
    if (entry.action == 'voided') {
      return 'voided ${d['voided_approvals'] ?? 1} approval(s) because content '
          'version ${d['new_version_number'] ?? '?'} was created';
    }
    if (d['content_hash'] != null) {
      final String hash = d['content_hash'].toString();
      final String short = hash.length > 8 ? hash.substring(0, 8) : hash;
      return 'version ${d['version_number'] ?? '?'} · sha256 $short…';
    }
    if (d['version_number'] != null) return 'version ${d['version_number']}';
    if (d['rule_id'] != null) return '${d['rule_id']} v${d['rule_version'] ?? '?'}';
    return entry.channel;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<LedgerEntry>>(
      future: _future,
      isEmpty: (List<LedgerEntry> d) => d.isEmpty,
      emptyMessage: 'The ledger is empty.\nSubmit and approve something to fill it.',
      onRetry: () => setState(() => _future = _load()),
      builder: (BuildContext context, List<LedgerEntry> rows) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length + 1,
          itemBuilder: (BuildContext context, int i) {
            if (i == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Append-only audit log. Entries are never edited or deleted — the '
                  'database refuses. SYSTEM entries are written by the database itself.',
                  style: TextStyle(fontSize: 11.5, color: Bg.unsupported, height: 1.6),
                ),
              );
            }
            final LedgerEntry entry = rows[i - 1];
            final bool system = entry.actorType == 'SYSTEM';
            final Color colour = _colour(entry.action);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colour.withAlpha(28),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon(entry.action), size: 15, color: colour),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Bg.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Bg.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              StatusChip(
                                entry.action,
                                colour: colour,
                                filled: entry.action == 'voided' ||
                                    entry.action == 'approved',
                              ),
                              const SizedBox(width: 8),
                              StatusChip(
                                system ? 'SYSTEM' : 'USER',
                                colour: system ? Bg.voided : Bg.primary,
                              ),
                              const Spacer(),
                              Text(
                                shortDate(entry.occurredAt),
                                style: const TextStyle(
                                    fontSize: 11, color: Bg.unsupported),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _headline(entry),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Bg.ink,
                            ),
                          ),
                          if (entry.reason != null) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              entry.reason!,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Bg.ink, height: 1.45),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            _detail(entry),
                            style: const TextStyle(
                                fontSize: 11, color: Bg.unsupported, height: 1.5),
                          ),
                        ],
                      ),
                    ),
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
