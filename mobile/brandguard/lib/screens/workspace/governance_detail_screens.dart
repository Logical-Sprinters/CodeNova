import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

class _GovernancePage extends StatelessWidget {
  const _GovernancePage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Map<String, String>> items;

  static const navy = Color(0xFF142C3B);
  static const darkNavy = Color(0xFF001725);
  static const teal = Color(0xFF006B5E);
  static const background = Color(0xFFF7F8F6);
  static const border = Color(0xFFE5EAE7);
  static const secondary = Color(0xFF73787C);

  TextStyle _style({double size = 12, FontWeight weight = FontWeight.w400,
    Color color = darkNavy}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, color: color);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background, elevation: 0, foregroundColor: darkNavy,
        title: Text(title, style: _style(size: 17, weight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(icon, color: const Color(0xFF81F7E1), size: 30),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: _style(size: 15, weight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text(subtitle, style: _style(size: 10, color: Colors.white70)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          Text('DEMO RECORDS', style: _style(size: 10, weight: FontWeight.w800, color: teal)),
          const SizedBox(height: 10),
          ...items.map((item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item['title']!, style: _style(size: 12, weight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFEAF4EE),
                    borderRadius: BorderRadius.circular(7)),
                  child: Text(item['status']!, style: _style(size: 9, weight: FontWeight.w800, color: teal)),
                ),
              ]),
              const SizedBox(height: 7),
              Text(item['detail']!, style: _style(size: 10, color: secondary)),
              const SizedBox(height: 8),
              Text(item['meta']!, style: _style(size: 9, weight: FontWeight.w700, color: teal)),
            ]),
          )),
          const SizedBox(height: 6),
          Text(
            'These are illustrative frontend demo records. They are not cryptographically verified or connected to a backend ledger.',
            style: _style(size: 10, color: secondary),
          ),
        ],
      ),
    );
  }
}

class VersionHistoryScreen extends StatelessWidget {
  const VersionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const _GovernancePage(
    title: 'Version History',
    subtitle: 'Content versions and approval state',
    icon: Icons.history_rounded,
    items: [
      {'title': 'ApexShield Product Announcement', 'status': 'CURRENT',
       'detail': 'Current content version submitted for authorised review.',
       'meta': 'BG-2026-0002 • v1.2 • Demo record'},
      {'title': 'ApexShield Product Announcement', 'status': 'SUPERSEDED',
       'detail': 'Previous content version. Any earlier approval does not transfer to the current version.',
       'meta': 'BG-2026-0002 • v1.1 • Demo record'},
      {'title': 'ApexShield Product Announcement', 'status': 'DRAFT',
       'detail': 'Initial draft before the latest content changes.',
       'meta': 'BG-2026-0002 • v1.0 • Demo record'},
    ],
  );
}

class AuditLedgerScreen extends StatelessWidget {
  const AuditLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) => const _GovernancePage(
    title: 'Audit Ledger',
    subtitle: 'Timeline of governance events',
    icon: Icons.receipt_long_rounded,
    items: [
      {'title': 'Content submitted', 'status': 'RECORDED',
       'detail': 'Creator submitted ApexShield Product Announcement for brand review.',
       'meta': 'Event BG-EVT-004 • Demo timestamp'},
      {'title': 'Brand check completed', 'status': 'RECORDED',
       'detail': 'Demo check completed and findings were prepared for reviewer inspection.',
       'meta': 'Event BG-EVT-003 • Demo timestamp'},
      {'title': 'Changes requested', 'status': 'RECORDED',
       'detail': 'Authorised reviewer requested changes with a written rationale.',
       'meta': 'Event BG-EVT-002 • Demo timestamp'},
      {'title': 'Guideline updated', 'status': 'RECORDED',
       'detail': 'A brand guideline entry was updated in the demo workspace.',
       'meta': 'Event BG-EVT-001 • Demo timestamp'},
    ],
  );
}

class ProcessingReceiptsScreen extends StatelessWidget {
  const ProcessingReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _GovernancePage(
    title: 'Processing Receipts',
    subtitle: 'Details recorded for a brand-check run',
    icon: Icons.fact_check_outlined,
    items: [
      {'title': 'Brand check • ApexShield Product Announcement', 'status': 'COMPLETED',
       'detail': 'Checks: content metadata, demo guideline scan, source-reference review. Reviewer approval is still separate.',
       'meta': 'Run ID BG-RUN-0002 • Content v1.2 • Demo receipt'},
      {'title': 'Brand check • Social campaign draft', 'status': 'COMPLETED',
       'detail': 'Checks: channel context, tone rules and claim references (illustrative).',
       'meta': 'Run ID BG-RUN-0001 • Content v1.0 • Demo receipt'},
    ],
  );
}
