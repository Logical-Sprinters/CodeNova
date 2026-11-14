
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import '../review/review_queue_screen.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() =>
      _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  static const navy = Color(0xFF142C3B);
  static const teal = Color(0xFF006B5E);
  static const background = Color(0xFFF7F8F5);
  static const secondary = Color(0xFF78868C);
  static const border = Color(0xFFE5ECE9);
  static const green = Color(0xFF4B9475);
  static const red = Color(0xFFC96B6B);
  static const amber = Color(0xFFB98742);

  String selectedPeriod = 'All Time';

  List<Map<String, dynamic>> get records => ReviewQueueData.reviews;

  int get total => records.length;

  int get pending =>
      records.where((r) => r['status'] == 'Pending').length;

  int get approved =>
      records.where((r) => r['status'] == 'Approved').length;

  int get rejected =>
      records.where((r) => r['status'] == 'Rejected').length;

  int get changesRequested =>
      records.where((r) => r['status'] == 'Changes Requested').length;

  int get reviewed => approved + rejected + changesRequested;

  double get approvalRate =>
      reviewed == 0 ? 0 : approved / reviewed * 100;

  int get totalFindings => records.fold<int>(
        0,
        (sum, r) => sum + ((r['findings'] as num?)?.toInt() ?? 0),
      );

  int _riskCount(String risk) =>
      records.where((r) => r['risk'] == risk).length;

  TextStyle style({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = navy,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  @override
  void initState() {
    super.initState();
    ReviewQueueData.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _exportReport() async {
    final buffer = StringBuffer();

    buffer.writeln(
      'ID,Title,Creator,Channel,Status,Risk,Findings,Version',
    );

    for (final r in records) {
      String safe(dynamic value) =>
          '"${(value ?? '').toString().replaceAll('"', '""')}"';

      buffer.writeln([
        safe(r['id']),
        safe(r['title']),
        safe(r['creator']),
        safe(r['channel']),
        safe(r['status']),
        safe(r['risk']),
        safe(r['findings']),
        safe(r['version']),
      ].join(','));
    }

    await Clipboard.setData(
      ClipboardData(text: buffer.toString()),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV report copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: navy,
          ),
        ),
        title: Text(
          'Admin Analytics',
          style: style(size: 18, weight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _exportReport,
            tooltip: 'Copy CSV report',
            icon: const Icon(
              Icons.file_download_outlined,
              color: teal,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: teal,
        onRefresh: () async {
          await ReviewQueueData.initialize();
          if (mounted) setState(() {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _heroCard(),
            const SizedBox(height: 18),
            _sectionTitle('Performance Overview', 'LIVE RECORDS'),
            const SizedBox(height: 11),
            _statsGrid(),
            const SizedBox(height: 22),
            _sectionTitle('Review Performance', 'STATUS BREAKDOWN'),
            const SizedBox(height: 11),
            _reviewChart(),
            const SizedBox(height: 22),
            _sectionTitle('Risk Distribution', 'CONTENT RISK'),
            const SizedBox(height: 11),
            _riskCard(),
            const SizedBox(height: 22),
            _sectionTitle('Governance Insights', 'KEY METRICS'),
            const SizedBox(height: 11),
            _insightsCard(),
            const SizedBox(height: 22),
            _sectionTitle('Recent Decisions', 'AUDIT OVERVIEW'),
            const SizedBox(height: 11),
            _recentDecisions(),
            const SizedBox(height: 20),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [navy, Color(0xFF205064)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF81F7E1),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'ADMIN CONTROL CENTER',
                style: style(
                  size: 9,
                  weight: FontWeight.w800,
                  color: const Color(0xFF81F7E1),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'LOCAL DATA',
                  style: style(
                    size: 8,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Governance at a glance.',
            style: style(
              size: 21,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Monitor brand checks, review outcomes and content risks.',
            style: style(size: 11, color: Colors.white70),
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              _heroMetric('TOTAL CHECKS', '$total'),
              const SizedBox(width: 27),
              _heroMetric(
                'APPROVAL RATE',
                '${approvalRate.toStringAsFixed(0)}%',
              ),
              const SizedBox(width: 27),
              _heroMetric('PENDING', '$pending'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: style(
              size: 22,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style(
              size: 8,
              weight: FontWeight.w700,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String label) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: style(size: 15, weight: FontWeight.w800),
          ),
        ),
        Text(
          label,
          style: style(
            size: 8,
            weight: FontWeight.w800,
            color: teal,
          ),
        ),
      ],
    );
  }

  Widget _statsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _statCard(
          'Total Checks',
          '$total',
          Icons.folder_open_rounded,
          navy,
          const Color(0xFFE8F6FF),
        ),
        _statCard(
          'Approved',
          '$approved',
          Icons.verified_rounded,
          green,
          const Color(0xFFEAF4EE),
        ),
        _statCard(
          'Pending',
          '$pending',
          Icons.schedule_rounded,
          amber,
          const Color(0xFFFBF4E8),
        ),
        _statCard(
          'Rejected',
          '$rejected',
          Icons.cancel_outlined,
          red,
          const Color(0xFFFBEFEE),
        ),
      ],
    );
  }

  Widget _statCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color tint,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: style(
                    size: 9,
                    weight: FontWeight.w800,
                    color: secondary,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 19),
            ],
          ),
          Text(
            value,
            style: style(size: 25, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _reviewChart() {
    final values = [
      ('Approved', approved, green),
      ('Pending', pending, amber),
      ('Changes Requested', changesRequested, const Color(0xFF6787A0)),
      ('Rejected', rejected, red),
    ];

    final maxValue = values.fold<int>(
      1,
      (max, item) => item.$2 > max ? item.$2 : max,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Submission status',
                style: style(size: 12, weight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '$total records',
                style: style(size: 10, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...values.map((item) {
            final fraction = item.$2 / maxValue;

            return Padding(
              padding: const EdgeInsets.only(bottom: 17),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.$1,
                          style: style(size: 10, weight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${item.$2}',
                        style: style(
                          size: 11,
                          weight: FontWeight.w800,
                          color: item.$3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 9,
                      backgroundColor: const Color(0xFFF0F2F1),
                      valueColor: AlwaysStoppedAnimation(item.$3),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 3),
          Text(
            'Approval rate is calculated from completed review decisions.',
            style: style(size: 9, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _riskCard() {
    final risks = [
      ('High Risk', _riskCount('High'), red),
      ('Medium Risk', _riskCount('Medium'), amber),
      ('Low Risk', _riskCount('Low'), green),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Content risk levels',
                  style: style(size: 12, weight: FontWeight.w800),
                ),
              ),
              Text(
                '$total total',
                style: style(size: 10, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...risks.map((risk) {
            final count = risk.$2;
            final ratio = total == 0 ? 0.0 : count / total;

            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: risk.$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      risk.$1,
                      style: style(size: 10, weight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFF0F2F1),
                        valueColor: AlwaysStoppedAnimation(risk.$3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.end,
                      style: style(size: 10, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _insightsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _insightRow(
            Icons.fact_check_outlined,
            'Total findings',
            '$totalFindings',
            'Across all submitted checks',
          ),
          const Divider(height: 22, color: border),
          _insightRow(
            Icons.rate_review_outlined,
            'Completed reviews',
            '$reviewed',
            'Approved, rejected or changes requested',
          ),
          const Divider(height: 22, color: border),
          _insightRow(
            Icons.pending_actions_rounded,
            'Awaiting action',
            '$pending',
            'Submissions pending review',
          ),
          const Divider(height: 22, color: border),
          _insightRow(
            Icons.percent_rounded,
            'Approval rate',
            '${approvalRate.toStringAsFixed(1)}%',
            'Approved / completed reviews',
          ),
        ],
      ),
    );
  }

  Widget _insightRow(
    IconData icon,
    String title,
    String value,
    String subtitle,
  ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE7F3F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: teal, size: 18),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: style(size: 11, weight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: style(size: 9, color: secondary),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: style(size: 16, weight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _recentDecisions() {
    final decisions = records.where((r) {
      final status = r['status'];
      return status == 'Approved' ||
          status == 'Rejected' ||
          status == 'Changes Requested';
    }).take(5).toList();

    if (decisions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Center(
          child: Text(
            'No completed review decisions yet.',
            style: style(size: 11, color: secondary),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: decisions.map((r) {
          final status = r['status']?.toString() ?? 'Unknown';
          final color = status == 'Approved'
              ? green
              : status == 'Rejected'
                  ? red
                  : amber;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  status == 'Approved'
                      ? Icons.check_circle_outline
                      : status == 'Rejected'
                          ? Icons.cancel_outlined
                          : Icons.edit_note_rounded,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (r['title'] ?? 'Untitled').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style(size: 10, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${r['id'] ?? ''} • ${r['decisionBy'] ?? 'Reviewer'}',
                        style: style(size: 9, color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  status,
                  style: style(
                    size: 9,
                    weight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: border),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: teal,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Analytics are calculated from locally stored demo records. '
              'Connect the backend for organisation-wide reporting.',
              style: style(size: 9, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
