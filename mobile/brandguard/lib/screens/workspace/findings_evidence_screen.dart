import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../review/review_queue_screen.dart';


class FindingsEvidenceScreen extends StatefulWidget {
  final String contentText;
  final ValueChanged<String> onContentUpdated;

  final String checkId;
  final String brandName;
  final String status;
  final String? receiptId;
  final List<dynamic> findings;

  const FindingsEvidenceScreen({
    super.key,
    required this.contentText,
    required this.onContentUpdated,
    required this.checkId,
    required this.brandName,
    required this.status,
    required this.findings,
    this.receiptId,
  });

  @override
  State<FindingsEvidenceScreen> createState() => _FindingsEvidenceScreenState();
}

class _FindingsEvidenceScreenState extends State<FindingsEvidenceScreen> {
  static const navy = Color(0xFF001725);
  static const teal = Color(0xFF258F83);
  static const background = Color(0xFFF7F8F6);
  static const border = Color(0xFFE5EAE7);
  static const secondary = Color(0xFF74838A);

  static const red = Color(0xFFC96B6B);
  static const redBg = Color(0xFFFBF0EF);

  static const amber = Color(0xFFB98742);
  static const amberBg = Color(0xFFFBF4E8);

  static const blue = Color(0xFF66869B);
  static const blueBg = Color(0xFFEEF3F6);

  String selectedFilter = 'All Findings';
  String selectedRewrite = 'Brand Balanced';
  bool priceFixApplied = false;
  bool toneFixApplied = false;
  bool submitted = false;

  String get updatedContent {
    String text = widget.contentText;

    if (priceFixApplied) {
      text = text.replaceAll(
        'Starting at just \$49/mo',
        'Starting at \$59/mo (standard enterprise tier)',
      );
    }

    if (toneFixApplied) {
      text = text.replaceAll(
        '100% uptime with zero data leaks',
        '99.99% SLA reliability with enterprise data protection',
      );
    }

    return text;
  }

  TextStyle style({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = navy,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showSource(String title, String details) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(title, style: style(size: 18, weight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(details, style: style(size: 13, color: secondary)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void applyPriceFix() {
    setState(() => priceFixApplied = true);
    widget.onContentUpdated(updatedContent);
    showMessage('Pricing suggestion applied to your draft.');
  }

  void applyToneFix() {
    setState(() => toneFixApplied = true);
    widget.onContentUpdated(updatedContent);
    showMessage('$selectedRewrite rewrite applied to your draft.');
  }

  void submitForReview() {
    if (submitted) return;

    widget.onContentUpdated(updatedContent);

    final contentId = ReviewQueueData.addSubmission(
      title: 'Q3 Apex Cloud Launch',
      creator: 'Current Creator',
      channel: 'LinkedIn',
      findings: 4,
      content: updatedContent,
    );

    setState(() {
      submitted = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(Icons.fact_check_rounded, color: teal, size: 42),
          title: Text(
            'Review Requested',
            style: style(size: 19, weight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your content has been successfully submitted to the authorised review queue.',
                style: style(size: 13, color: secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F5EF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      'CONTENT ID',
                      style: style(
                        size: 9,
                        weight: FontWeight.w800,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      contentId,
                      style: style(
                        size: 16,
                        weight: FontWeight.w800,
                        color: teal,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Status: Pending Authorised Review',
                      textAlign: TextAlign.center,
                      style: style(
                        size: 10,
                        weight: FontWeight.w700,
                        color: navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Final approval must come from an authorised reviewer.',
                style: style(size: 11, color: secondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Back to Dashboard'),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _contextLabel(),
                    const SizedBox(height: 12),
                    _statusCard(),
                    const SizedBox(height: 14),
                    _filters(),
                    const SizedBox(height: 12),
                    if (_visibleFindings.isNotEmpty)
                    ..._visibleFindings.map(_backendFindingCard),

                    if (_visibleFindings.isEmpty)
                    _emptyFilter(),
                  ],
                ),
              ),
            ),
            _bottomAction(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: navy),
          ),
          const Icon(Icons.verified_user_rounded, color: teal, size: 25),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Audit Inspection',
              style: style(size: 17, weight: FontWeight.w800),
            ),
          ),
          const CircleAvatar(
            radius: 17,
            backgroundColor: navy,
            child: Icon(Icons.person, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _contextLabel() {
    return Row(
      children: [
        const Icon(Icons.campaign_outlined, color: secondary, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Q3 Apex Cloud Launch • LinkedIn Carousel',
            style: style(size: 11, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: teal, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.status == 'review_required'
                    ? 'Review Required'
                    : 'Brand Check Complete',
                  style: style(size: 15, weight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: redBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.findings.length} FINDINGS',
                  style: style(size: 9, weight: FontWeight.w800, color: red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.policy_outlined, color: navy, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: style(size: 10, color: secondary),
                      children: [
                        TextSpan(
                          text: 'No aggregate score: ',
                          style: style(
                            size: 10,
                            weight: FontWeight.w800,
                            color: navy,
                          ),
                        ),
                        const TextSpan(
                          text: 'Every finding requires individual evidence-backed resolution or authorised sign-off before publication.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final filters = [
      'All Findings',
      'Rule Match',
      'AI Interpretation',
      'Unsupported',
      'Source Conflict',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final active = selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(filter),
              selected: active,
              onSelected: (_) {
                setState(() => selectedFilter = filter);
              },
              selectedColor: navy,
              backgroundColor: Colors.white,
              labelStyle: style(
                size: 10,
                weight: FontWeight.w700,
                color: active ? Colors.white : secondary,
              ),
              side: BorderSide(color: active ? navy : border),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> get _backendFindings {
  return widget.findings
      .whereType<Map>()
      .map((finding) => Map<String, dynamic>.from(finding))
      .toList();
  }

  List<Map<String, dynamic>> get _visibleFindings {
    if (selectedFilter == 'All Findings' ||
        selectedFilter == 'Rule Match') {
      return _backendFindings;
    }

    return [];
  }

  Widget _findingCard({
    required Widget child,
    required Color color,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.04),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }


  Widget _backendFindingCard(Map<String, dynamic> finding) {
    final ruleId = finding['rule_id']?.toString() ?? 'UNKNOWN';
    final severity = finding['severity']?.toString() ?? 'review';
    final message = finding['message']?.toString() ?? 'No description available.';
    final evidence = finding['evidence']?.toString() ?? '';

    final isCritical = severity.toLowerCase() == 'critical';
    final isReview = severity.toLowerCase() == 'review';

    final Color severityColor = isCritical
        ? red
        : isReview
            ? amber
            : blue;

    final Color severityBackground = isCritical
        ? redBg
        : isReview
            ? amberBg
            : blueBg;

    return _findingCard(
      color: severityColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tag('Rule Match', blue, blueBg),
              const SizedBox(width: 7),
              _tag(severity, severityColor, severityBackground),
              const Spacer(),
              Text(
                ruleId,
                style: style(size: 9, color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            message,
            style: style(size: 13, weight: FontWeight.w800),
          ),
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'MATCHED CONTENT',
              style: style(
                size: 9,
                weight: FontWeight.w800,
                color: secondary,
              ),
            ),
            const SizedBox(height: 6),
            _quoteBox(evidence, severityColor),
          ],
          const SizedBox(height: 10),
          Text(
            'Detected by the BrandGuard deterministic rule engine.',
            style: style(size: 10, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color, Color fill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label.toUpperCase(),
        style: style(size: 9, weight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _quoteBox(String text, Color highlightColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6FF),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text, style: style(size: 11, weight: FontWeight.w600)),
    );
  }

  Widget _emptyFilter() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Text(
        'No findings available in this category.',
        textAlign: TextAlign.center,
        style: style(size: 12, color: secondary),
      ),
    );
  }

  Widget _bottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'AI suggestions applied: '
                  '${(priceFixApplied ? 1 : 0) + (toneFixApplied ? 1 : 0)} of 4',
                  style: style(size: 9, color: secondary),
                ),
                Text(
                  '2 manual reviews required',
                  style: style(size: 9, color: red),
                ),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 49,
              child: ElevatedButton.icon(
                onPressed: submitted ? null : submitForReview,
                icon: const Icon(Icons.shield_outlined, size: 19),
                label: Text(
                  submitted
                      ? 'Submitted for Review'
                      : 'Submit for Authorised Review',
                  style: style(
                    size: 12,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: teal.withValues(alpha: 0.6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
