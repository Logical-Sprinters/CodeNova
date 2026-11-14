import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/widgets.dart';

/// Read-only in this build, and it earns its place by proving one claim: every
/// finding cites a version from this list, and this list shows which of them are
/// live today. Superseded and draft versions stay visible — that is the trail.
class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key});

  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  late Future<List<Rule>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Rule>> _load() async {
    final dynamic data = await Api.get('/rules');
    return (data as List<dynamic>)
        .map((dynamic e) => Rule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Rule>>(
      future: _future,
      isEmpty: (List<Rule> d) => d.isEmpty,
      emptyMessage: 'No rules imported. Run:  make db',
      onRetry: () => setState(() => _future = _load()),
      builder: (BuildContext context, List<Rule> rules) {
        final int live = rules.where((Rule r) => r.isLive).length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              '${rules.length} rule versions · $live live today.\n'
              'A finding may only cite a version that is live on the date of the '
              'check. Superseded and draft versions stay visible on purpose.',
              style: const TextStyle(fontSize: 11.5, color: Bg.unsupported, height: 1.6),
            ),
            const SizedBox(height: 16),
            for (final Rule rule in rules) ...<Widget>[
              _RuleCard(rule: rule),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});

  final Rule rule;

  @override
  Widget build(BuildContext context) {
    final Color colour = !rule.isLive
        ? (rule.status == 'EXPIRED' ? Bg.conflict : Bg.voided)
        : (rule.status == 'ACTIVE' ? Bg.approved : Bg.interpretation);

    return Container(
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
              Text(
                '${rule.id} v${rule.version}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Bg.primary,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(rule.status, colour: colour),
              if (rule.isLive) ...<Widget>[
                const SizedBox(width: 6),
                const StatusChip('LIVE', colour: Bg.approved, filled: true),
              ],
              const Spacer(),
              Text(rule.type, style: const TextStyle(fontSize: 11, color: Bg.unsupported)),
            ],
          ),
          const SizedBox(height: 8),
          Text(rule.text, style: const TextStyle(fontSize: 13.5, height: 1.5, color: Bg.ink)),
          const SizedBox(height: 8),
          Text(
            'from ${rule.effectiveFrom}'
            '${rule.expiresOn == null ? ', no end date' : ' to ${rule.expiresOn}'}'
            '  ·  ${rule.sourceFile}'
            '${rule.sourcePage == null ? '' : ' p${rule.sourcePage}'}'
            '  ·  ${rule.channels.join(', ')}'
            '${rule.priceSensitive ? '  ·  price-sensitive' : ''}',
            style: const TextStyle(fontSize: 10.5, color: Bg.unsupported, height: 1.5),
          ),
        ],
      ),
    );
  }
}
