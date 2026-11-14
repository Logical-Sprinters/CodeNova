import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'findings_evidence_screen.dart';

class NewBrandCheckScreen extends StatefulWidget {
  const NewBrandCheckScreen({super.key});

  @override
  State<NewBrandCheckScreen> createState() => _NewBrandCheckScreenState();
}

class _NewBrandCheckScreenState extends State<NewBrandCheckScreen> {
  static const navy = Color(0xFF001725);
  static const teal = Color(0xFF258F83);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF7F8F6);
  static const lightBlue = Color(0xFFE8F6FF);
  static const border = Color(0xFFE5EAE7);
  static const secondary = Color(0xFF73787C);

  final TextEditingController _contentController = TextEditingController(
    text:
        'Accelerate your workflow with ApexShield. '
        'Starting at just \$49/mo, our enterprise platform '
        'guarantees 100% uptime with zero data leaks in any '
        'region. Trusted by 95% of Fortune 500 leaders worldwide.',
  );

  bool pricingPolicy = true;
  bool compliancePolicy = true;
  bool tonePolicy = true;

  bool assetAttached = true;
  bool isChecking = false;

  int get wordCount {
    final text = _contentController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  int get charCount => _contentController.text.length;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  TextStyle style({
    double size = 14,
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
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
      ),
    );
  }

  void formatSelection(String prefix, String suffix) {
    final selection = _contentController.selection;

    if (!selection.isValid) return;

    final text = _contentController.text;
    final selectedText = selection.textInside(text);

    if (selectedText.isEmpty) return;

    final replacement = '$prefix$selectedText$suffix';

    _contentController.value = TextEditingValue(
      text:
          selection.textBefore(text) + replacement + selection.textAfter(text),
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
  }

  void insertBullet() {
    final selection = _contentController.selection;

    if (!selection.isValid) return;

    final text = _contentController.text;
    final selectedText = selection.textInside(text);

    if (selectedText.isEmpty) {
      final position = selection.baseOffset;
      final updated = text.replaceRange(position, position, '\n• ');

      _contentController.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: position + 3),
      );
    } else {
      final replacement = selectedText
          .split('\n')
          .map((line) => '• $line')
          .join('\n');

      _contentController.value = TextEditingValue(
        text:
            selection.textBefore(text) +
            replacement +
            selection.textAfter(text),
        selection: TextSelection.collapsed(
          offset: selection.start + replacement.length,
        ),
      );
    }
  }

  // UPDATED: Run Brand Check opens Findings & Evidence screen.
  Future<void> runBrandCheck() async {
    FocusScope.of(context).unfocus();

    if (_contentController.text.trim().isEmpty) {
      showMessage('Please enter content before running a check.');
      return;
    }

    setState(() => isChecking = true);

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => isChecking = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FindingsEvidenceScreen(
          contentText: _contentController.text,
          onContentUpdated: (updatedText) {
            _contentController.text = updatedText;
          },
        ),
      ),
    );
  }

  void saveDraft() {
    showMessage('Draft saved locally for this demo session.');
  }

  void editCampaignDetails() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Campaign Details',
            style: style(size: 18, weight: FontWeight.w800),
          ),
          content: Text(
            'Campaign: Q3 Global Cloud\n'
            'Channel: LinkedIn\n'
            'Target Date: October 24, 2024',
            style: style(size: 13, color: secondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Close', style: style(color: teal)),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _stepper(),
                    const SizedBox(height: 16),
                    _campaignSummary(),
                    const SizedBox(height: 22),
                    _editorSection(),
                    const SizedBox(height: 24),
                    _assetsSection(),
                    const SizedBox(height: 24),
                    _policySection(),
                    const SizedBox(height: 24),
                    _submissionSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header with Dashboard back button.
  Widget _header() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Dashboard',
            onPressed: () {
              Navigator.pop(context);
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 38,
            ),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: navy,
              size: 22,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: navy,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: mint,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BrandGuard',
                style: style(size: 17, weight: FontWeight.w800),
              ),
              Text('Workspace', style: style(size: 10, color: secondary)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () => showMessage('No new notifications.'),
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: secondary,
            ),
          ),
          const CircleAvatar(
            radius: 17,
            backgroundColor: navy,
            child: Icon(Icons.person, color: Colors.white, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    final labels = ['Details', 'Content', 'Assets', 'Review'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STEP 2 OF 4',
              style: style(size: 10, weight: FontWeight.w800, color: teal),
            ),
            Text(
              'Content & Messaging',
              style: style(size: 11, color: secondary),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: List.generate(4, (index) {
            final completed = index == 0;
            final active = index == 1;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: completed || active ? teal : border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[index],
                      style: style(
                        size: 9,
                        weight: active || completed
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: active || completed ? teal : secondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _campaignSummary() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: lightBlue,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: teal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q3 Global Cloud  •  LinkedIn',
                  style: style(size: 12, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'Target Date: Oct 24, 2024',
                  style: style(size: 10, color: secondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: editCampaignDetails,
            child: Text(
              'Edit',
              style: style(size: 12, weight: FontWeight.w800, color: teal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Draft Copy / Marketing Message',
                style: style(size: 16, weight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.cloud_done_rounded, color: teal, size: 16),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Your content is editable during this demo session.',
          style: style(size: 10, color: secondary),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 5,
                ),
                color: lightBlue,
                child: Row(
                  children: [
                    _formatButton(
                      Icons.format_bold,
                      () => formatSelection('**', '**'),
                    ),
                    _formatButton(
                      Icons.format_italic,
                      () => formatSelection('_', '_'),
                    ),
                    _formatButton(
                      Icons.link_rounded,
                      () => formatSelection('[', '](https://example.com)'),
                    ),
                    _formatButton(Icons.format_list_bulleted, insertBullet),
                    _formatButton(
                      Icons.format_quote_rounded,
                      () => formatSelection('"', '"'),
                    ),
                    const Spacer(),
                    _formatButton(Icons.format_clear_rounded, () {
                      _contentController.clear();
                      setState(() {});
                    }),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15),
                child: TextField(
                  controller: _contentController,
                  minLines: 6,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                  style: style(size: 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Type or paste your marketing copy...',
                    hintStyle: style(size: 12, color: secondary),
                  ),
                ),
              ),
              Container(
                color: lightBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notes_rounded, color: teal, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      '$wordCount words',
                      style: style(size: 10, weight: FontWeight.w700),
                    ),
                    const SizedBox(width: 15),
                    const Icon(Icons.pin_rounded, color: teal, size: 15),
                    const SizedBox(width: 5),
                    Text(
                      '$charCount chars',
                      style: style(size: 10, weight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      '~${(wordCount / 3).ceil()} sec read',
                      style: style(size: 10, color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formatButton(IconData icon, VoidCallback onTap) {
    return IconButton(
      onPressed: () {
        onTap();
        setState(() {});
      },
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: secondary),
    );
  }

  Widget _assetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined, color: teal, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Attached Visual Assets',
                style: style(size: 16, weight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => assetAttached = true);
                showMessage('Demo asset attached.');
              },
              icon: const Icon(Icons.add, size: 17),
              label: Text(
                'Add More',
                style: style(size: 11, weight: FontWeight.w800, color: teal),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (assetAttached)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 72,
                      width: 78,
                      decoration: BoxDecoration(
                        color: navy,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.image_rounded,
                        color: mint,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'apex_banner_v2.png',
                            style: style(size: 12, weight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '1.8 MB • 1200 × 628 px',
                            style: style(size: 10, color: secondary),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: lightBlue,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              'OCR: 4 slogans identified',
                              style: style(
                                size: 9,
                                weight: FontWeight.w700,
                                color: teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 22, color: border),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => showMessage(
                        'Asset replacement will be connected later.',
                      ),
                      icon: const Icon(Icons.sync_alt, size: 16),
                      label: const Text('Replace'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => assetAttached = false);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          InkWell(
            onTap: () {
              setState(() => assetAttached = true);
              showMessage('Demo asset attached.');
            },
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: teal,
                    size: 35,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add visual asset',
                    style: style(size: 13, weight: FontWeight.w800),
                  ),
                  Text(
                    'Tap to attach a demo asset',
                    style: style(size: 10, color: secondary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _policySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: teal, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Inspection Policy Engine',
                style: style(size: 16, weight: FontWeight.w800),
              ),
            ),
            Text(
              '3 RULESETS',
              style: style(size: 9, weight: FontWeight.w800, color: teal),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _policyCard(
          icon: Icons.verified_outlined,
          title: 'Pricing & Numeric Claim Verification',
          description:
              'Cross-checks prices and numeric claims against approved sales matrices.',
          value: pricingPolicy,
          onChanged: (value) {
            setState(() => pricingPolicy = value);
          },
        ),
        const SizedBox(height: 9),
        _policyCard(
          icon: Icons.policy_outlined,
          title: 'Regulatory & Compliance Guidelines',
          description:
              'Scans absolute statements and checks required disclaimers.',
          value: compliancePolicy,
          onChanged: (value) {
            setState(() => compliancePolicy = value);
          },
        ),
        const SizedBox(height: 9),
        _policyCard(
          icon: Icons.psychology_outlined,
          title: 'Tone & Voice Brand Adherence',
          description:
              'Validates authority, confident humility and terminology consistency.',
          value: tonePolicy,
          onChanged: (value) {
            setState(() => tonePolicy = value);
          },
        ),
      ],
    );
  }

  Widget _policyCard({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            height: 35,
            width: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFE1F5EF),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(icon, color: teal, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: style(size: 11, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(description, style: style(size: 10, color: secondary)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: teal,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _submissionSection() {
    final activePolicies = [
      pricingPolicy,
      compliancePolicy,
      tonePolicy,
    ].where((value) => value).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 49,
                  child: OutlinedButton.icon(
                    onPressed: saveDraft,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: lightBlue,
                      foregroundColor: navy,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      'Draft',
                      style: style(size: 12, weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 49,
                  child: ElevatedButton.icon(
                    onPressed: isChecking ? null : runBrandCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: teal.withValues(alpha: 0.6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: isChecking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.security_rounded, size: 19),
                    label: Text(
                      isChecking ? 'Checking...' : 'Run Brand Check',
                      style: style(
                        size: 12,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_outlined, color: teal, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$activePolicies policy rules active • Demo inspection only',
                  textAlign: TextAlign.center,
                  style: style(size: 10, color: secondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
