import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

/// The product. Everything a person needs to decide about one version:
/// the copy with its findings anchored to it, the rule each finding cites, three
/// ways to repair it, and one button a reviewer is allowed to press.
class FindingsScreen extends StatefulWidget {
  const FindingsScreen({super.key, required this.contentId});

  final String contentId;

  @override
  State<FindingsScreen> createState() => _FindingsScreenState();
}

class _FindingsScreenState extends State<FindingsScreen> {
  late Future<ContentDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ContentDetail> _load() async {
    final dynamic data = await Api.get('/content/${widget.contentId}');
    return ContentDetail.fromJson(data as Map<String, dynamic>);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<dynamic> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: Bg.tertiary),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Bg.confirmed),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCopy(String current) async {
    final TextEditingController controller =
        TextEditingController(text: current);
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Edit the copy'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create new version'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await _run(
      () => Api.post('/content/${widget.contentId}/versions',
          <String, dynamic>{'text': controller.text}),
      'New version created. Any standing approval is now void.',
    );
  }

  Future<void> _override(Finding finding) async {
    final TextEditingController controller = TextEditingController();
    final bool? recorded = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Override this finding'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(finding.message,
                style: const TextStyle(fontSize: 13, color: Bg.unsupported)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Why is this rule wrong or inapplicable? (required)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stored against this rule version, and counted as a clarity ticket.',
              style: TextStyle(fontSize: 11, color: Bg.unsupported),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record override'),
          ),
        ],
      ),
    );
    if (recorded != true || controller.text.trim().length < 3) return;
    await _run(
      () => Api.post('/findings/${finding.id}/override', <String, dynamic>{
        'reason_text': controller.text.trim(),
        'reason_code': 'rule_unclear',
      }),
      'Override recorded against ${finding.ruleId} v${finding.ruleVersion}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Findings')),
      body: AsyncBody<ContentDetail>(
        future: _future,
        onRetry: _reload,
        builder: (BuildContext context, ContentDetail detail) {
          return Stack(
            children: <Widget>[
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: <Widget>[
                  _header(detail),
                  const SizedBox(height: 16),
                  _copyCard(detail),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Text(
                        '${detail.findings.length} FINDINGS',
                        style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Bg.unsupported,
                        ),
                      ),
                      const Spacer(),
                      if (detail.checkOutcome != null)
                        Text(
                          'check ${detail.checkOutcome}',
                          style: const TextStyle(
                              fontSize: 11, color: Bg.unsupported),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (detail.findings.isEmpty)
                    const EmptyState(
                      message: 'No findings on this version.\n\n'
                          'That means every live rule that applies was satisfied — '
                          'not that the copy is good.',
                    )
                  else
                    for (final Finding finding in detail.findings) ...<Widget>[
                      _FindingCard(
                        finding: finding,
                        busy: _busy,
                        onAccept: (String label) => _run(
                          () => Api.post(
                              '/findings/${finding.id}/rewrites/$label'),
                          'Repair $label accepted — a new version was created and re-checked.',
                        ),
                        onOverride: () => _override(finding),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
              Positioned(
                  left: 16, right: 16, bottom: 16, child: _actions(detail)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(ContentDetail detail) {
    final String state = detail.approval?.state ?? 'DRAFT';
    final Color colour = StatusStyle.colour(state);
    final bool inForce = state == 'APPROVED' || state == 'VOID';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            StatusChip('v${detail.versionNumber}', colour: Bg.primary),
            const SizedBox(width: 8),
            StatusChip(detail.channel, colour: Bg.primary),
            const SizedBox(width: 8),
            StatusChip(StatusStyle.label(state),
                colour: colour, filled: state == 'APPROVED'),
            const Spacer(),
            HashLabel(detail.hash),
          ],
        ),
        if (inForce && detail.approval?.voidedAt != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Bg.voided.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Bg.voided.withAlpha(80)),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.link_off, size: 18, color: Bg.voided),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Approval invalidated. This content has changed since it was '
                    'approved (${shortDate(detail.approval!.voidedAt!)}).',
                    style: const TextStyle(
                        fontSize: 12, color: Bg.ink, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _copyCard(ContentDetail detail) {
    final List<TextSpan> spans = <TextSpan>[];
    int cursor = 0;

    final List<Finding> anchored = detail.findings
        .where((Finding f) =>
            f.spanStart != null &&
            f.spanEnd != null &&
            f.spanStart! >= cursor &&
            f.spanEnd! <= detail.text.length)
        .toList()
      ..sort((Finding a, Finding b) => a.spanStart!.compareTo(b.spanStart!));

    for (final Finding finding in anchored) {
      final int start = finding.spanStart!;
      final int end = finding.spanEnd!;
      if (start > cursor) {
        spans.add(TextSpan(text: detail.text.substring(cursor, start)));
      }
      final Color colour = StatusStyle.colour(finding.status);
      spans.add(
        TextSpan(
          text: detail.text.substring(start, end),
          style: TextStyle(
            backgroundColor: colour.withAlpha(46),
            color: colour,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < detail.text.length) {
      spans.add(TextSpan(text: detail.text.substring(cursor)));
    }

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
          const Text(
            'THE COPY · HIGHLIGHTS ARE FINDINGS',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: Bg.unsupported,
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                height: 1.6,
                color: Bg.ink,
              ),
              children: spans,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(ContentDetail detail) {
    final int blocking =
        detail.findings.where((Finding f) => f.blocksApproval).length;
    final bool canApprove = session.canApprove && blocking == 0;

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _editCopy(detail.text),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit copy'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: (_busy || !canApprove)
                ? null
                : () => _run(
                      () => Api.post('/content/${detail.id}/approve'),
                      'Approved. Bound to the hash of v${detail.versionNumber}.',
                    ),
            child: Text(
              !session.canApprove
                  ? 'Reviewer approval required'
                  : blocking == 0
                      ? 'Approve v${detail.versionNumber}'
                      : '$blocking blocking finding(s)',
            ),
          ),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.busy,
    required this.onAccept,
    required this.onOverride,
  });

  final Finding finding;
  final bool busy;
  final void Function(String label) onAccept;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final Color colour = StatusStyle.colour(finding.status);

    // The coloured edge is a left border, not a stretched Row child: a Row with
    // CrossAxisAlignment.stretch inside a scrolling list has no bounded height to
    // stretch into, and would throw at runtime.
    return Container(
      decoration: BoxDecoration(
        color: Bg.card,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: colour, width: 5),
          top: const BorderSide(color: Bg.line),
          right: const BorderSide(color: Bg.line),
          bottom: const BorderSide(color: Bg.line),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                StatusChip(StatusStyle.label(finding.status), colour: colour),
                const Spacer(),
                Text(
                  '${finding.ruleId} v${finding.ruleVersion}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Bg.unsupported,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              finding.message,
              style:
                  const TextStyle(fontSize: 13.5, height: 1.5, color: Bg.ink),
            ),
            if (finding.quote.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Bg.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Bg.line),
                ),
                child: Text(
                  '“${finding.quote}”',
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Bg.ink,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '${finding.ruleText}  ·  ${finding.sourceFile}'
              '${finding.sourcePage == null ? '' : ' p${finding.sourcePage}'}'
              '${finding.ruleExpires == null ? '' : '  ·  expires ${finding.ruleExpires}'}'
              '${finding.overrideCount > 0 ? '  ·  overridden ×${finding.overrideCount}' : ''}',
              style: const TextStyle(
                fontSize: 11,
                color: Bg.unsupported,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'REPAIR IT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: Bg.unsupported,
              ),
            ),
            const SizedBox(height: 8),
            for (final Rewrite rewrite in finding.rewrites)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: busy ? null : () => onAccept(rewrite.label),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Bg.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        StatusChip(rewrite.label,
                            colour: Bg.secondary, filled: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                rewrite.strategy.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 0.6,
                                  color: Bg.unsupported,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                rewrite.text,
                                style:
                                    const TextStyle(fontSize: 13, height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onOverride,
                icon: const Icon(Icons.gavel_outlined, size: 16),
                label: const Text('Override with a reason'),
                style: TextButton.styleFrom(foregroundColor: Bg.unsupported),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
