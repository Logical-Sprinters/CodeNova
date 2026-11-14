import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'new_brand_check_screen.dart';
import 'brand_guidelines_screen.dart';
import 'upload_rule_screen.dart';
import 'fact_sources_screen.dart';
import 'governance_detail_screens.dart';
import '../review/review_queue_screen.dart';
import '../dashboard/admin_analytics_screen.dart';

class WorkspaceHubScreen extends StatelessWidget {
  const WorkspaceHubScreen({super.key});

  static const navy = Color(0xFF142C3B);
  static const darkNavy = Color(0xFF001725);
  static const teal = Color(0xFF006B5E);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF7F8F6);
  static const border = Color(0xFFE5EAE7);
  static const secondary = Color(0xFF73787C);

  TextStyle _style({double size = 13, FontWeight weight = FontWeight.w400,
    Color color = darkNavy}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, color: color);

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background, elevation: 0, foregroundColor: darkNavy,
        title: Text('Workspace', style: _style(size: 17, weight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.layers_rounded, color: mint, size: 34),
              const SizedBox(width: 13),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Brand Governance Workspace',
                    style: _style(size: 15, weight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 5),
                  Text('Manage checks, policies, evidence and review workflows.',
                    style: _style(size: 10, color: Colors.white70)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 22),
          _section('CONTENT WORKFLOW'),
          _tile(context, 'New Brand Check', 'Submit content for a brand compliance check.',
            Icons.shield_outlined, const Color(0xFFE1F3EE), teal,
            () => _open(context, const NewBrandCheckScreen())),
          _tile(context, 'Review Queue', 'Review submissions and record decisions.',
            Icons.assignment_turned_in_rounded, const Color(0xFFE8F6FF), navy,
            () => _open(context, const ReviewQueueScreen())),
          const SizedBox(height: 18),
          _section('BRAND KNOWLEDGE'),
          _tile(context, 'Brand Guidelines', 'Manage tone, visual identity and compliance rules.',
            Icons.menu_book_rounded, const Color(0xFFEAF4EE), teal,
            () => _open(context, const BrandGuidelinesScreen())),
          _tile(context, 'Upload Rule', 'Add a brand rule to the local demo library.',
            Icons.upload_file_rounded, const Color(0xFFE8F6FF), navy,
            () => _open(context, const UploadRuleScreen())),
          _tile(context, 'Fact Sources', 'Maintain reference sources for factual claims.',
            Icons.fact_check_rounded, const Color(0xFFDDE8EF), navy,
            () => _open(context, const FactSourcesScreen())),
          const SizedBox(height: 18),
          _section('GOVERNANCE & INSIGHTS'),
          _tile(context, 'Analytics', 'View review and governance activity metrics.',
            Icons.analytics_rounded, const Color(0xFFFBF4E8), const Color(0xFFB98742),
            () => _open(context, const AdminAnalyticsScreen())),
          _tile(context, 'Version History', 'View sample content versions and approval validity.',
            Icons.history_rounded, const Color(0xFFE8F6FF), navy,
            () => _open(context, const VersionHistoryScreen())),
          _tile(context, 'Audit Ledger', 'Explore the sample governance event timeline.',
            Icons.receipt_long_rounded, const Color(0xFFEAF4EE), teal,
            () => _open(context, const AuditLedgerScreen())),
          _tile(context, 'Processing Receipts', 'Inspect details recorded for a brand-check run.',
            Icons.fact_check_outlined, const Color(0xFFFBF4E8), const Color(0xFFB98742),
            () => _open(context, const ProcessingReceiptsScreen())),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: _style(size: 10, weight: FontWeight.w800, color: teal)),
  );

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon,
      Color tint, Color accent, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: accent, size: 21),
        ),
        title: Text(title, style: _style(size: 12, weight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(subtitle, style: _style(size: 10, color: secondary)),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: secondary),
      ),
    );
  }
}
