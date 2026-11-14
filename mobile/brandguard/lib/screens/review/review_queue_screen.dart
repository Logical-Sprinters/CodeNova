import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewQueueData {
  static const String _storageKey = 'brandguard_reviews_v1';

  static final List<Map<String, dynamic>> reviews = [
    {
      'id': 'BG-2026-001',
      'title': 'Q3 Global Cloud Launch',
      'creator': 'Alex Morgan',
      'channel': 'LinkedIn',
      'date': '14 Nov 2026',
      'status': 'Pending',
      'findings': 4,
      'version': 'v1.0',
      'risk': 'High',
      'description': 'Enterprise cloud campaign containing pricing, uptime and customer adoption claims.',
    },
    {
      'id': 'BG-2026-002',
      'title': 'ApexShield Product Announcement',
      'creator': 'Sarah Chen',
      'channel': 'Instagram',
      'date': '13 Nov 2026',
      'status': 'Pending',
      'findings': 2,
      'version': 'v2.0',
      'risk': 'Medium',
      'description': 'Product announcement with claims requiring authorised source verification.',
    },
    {
      'id': 'BG-2026-003',
      'title': 'Enterprise Security Newsletter',
      'creator': 'Jordan Lee',
      'channel': 'Email',
      'date': '12 Nov 2026',
      'status': 'Changes Requested',
      'findings': 3,
      'version': 'v1.2',
      'risk': 'Medium',
      'description': 'Newsletter requiring revised compliance language and supporting evidence.',
    },
    {
      'id': 'BG-2026-004',
      'title': 'Cloud Migration Campaign',
      'creator': 'Taylor Smith',
      'channel': 'Website',
      'date': '11 Nov 2026',
      'status': 'Approved',
      'findings': 1,
      'version': 'v1.0',
      'risk': 'Low',
      'description': 'Reviewed campaign with documented evidence and authorised approval.',
    },
  ];

  static int _nextId = 5;
  static bool _isInitialized = false;
  static Future<void>? _initializationFuture;

  /// Loads persisted reviews once. Existing demo records are retained on first launch.
  static Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    return _initializationFuture ??= _loadFromStorage();
  }

  static Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString(_storageKey);

      if (savedData != null) {
        final decoded = jsonDecode(savedData);
        if (decoded is List) {
          reviews
            ..clear()
            ..addAll(decoded.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ));
        }
      } else {
        await prefs.setString(_storageKey, jsonEncode(reviews));
      }

      _refreshNextId();
      _isInitialized = true;
    } catch (error) {
      // Keep the in-memory demo data usable if local storage cannot be read.
      _isInitialized = true;
    }
  }

  static Future<void> save() async {
    await initialize();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(reviews));
    } catch (_) {
      // The app remains usable in memory if persistence is unavailable.
    }
  }

  static void _refreshNextId() {
    var highestId = 0;
    for (final review in reviews) {
      final id = review['id']?.toString() ?? '';
      final match = RegExp(r'BG-\d{4}-(\d+)').firstMatch(id);
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > highestId) highestId = number;
    }
    _nextId = highestId + 1;
  }

  static String addSubmission({
    required String title,
    required String creator,
    required String channel,
    required int findings,
    required String content,
  }) {
    final id = 'BG-2026-${_nextId.toString().padLeft(3, '0')}';
    _nextId++;

    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final formattedDate =
        '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';

    reviews.insert(0, {
      'id': id,
      'title': title,
      'creator': creator,
      'channel': channel,
      'date': formattedDate,
      'status': 'Pending',
      'findings': findings,
      'version': 'v1.0',
      'risk': 'High',
      'description': 'Newly submitted content awaiting authorised review.',
      'content': content,
    });

    unawaited(save());
    return id;
  }

  static void recordDecision({
    required Map<String, dynamic> review,
    required String decision,
    required String reason,
    String reviewer = 'Authorised Reviewer',
  }) {
    review['status'] = decision;
    review['decisionReason'] = reason;
    review['decisionBy'] = reviewer;
    review['decisionAt'] = DateTime.now().toIso8601String();
    unawaited(save());
  }
}

class ReviewQueueScreen extends StatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  static const navy = Color(0xFF142C3B);
  static const teal = Color(0xFF258F83);
  static const background = Color(0xFFF7F8F5);
  static const border = Color(0xFFE5ECE9);
  static const secondary = Color(0xFF78868C);
  static const amber = Color(0xFFB98742);
  static const red = Color(0xFFC96B6B);

  String selectedTab = 'Pending';

  List<Map<String, dynamic>> get reviews => ReviewQueueData.reviews;

  @override
  void initState() {
    super.initState();
    ReviewQueueData.initialize().then((_) {
      if (mounted) setState(() {});
    });
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

  List<Map<String, dynamic>> get filteredReviews {
    if (selectedTab == 'All') return reviews;

    return reviews.where((item) => item['status'] == selectedTab).toList();
  }

  int get pendingCount =>
      reviews.where((item) => item['status'] == 'Pending').length;

  int get approvedCount =>
      reviews.where((item) => item['status'] == 'Approved').length;

  int get changesCount =>
      reviews.where((item) => item['status'] == 'Changes Requested').length;

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: navy,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color statusColor(String status) {
    switch (status) {
      case 'Approved':
        return teal;
      case 'Changes Requested':
        return amber;
      case 'Rejected':
        return red;
      default:
        return const Color(0xFF66869B);
    }
  }

  Color riskColor(String risk) {
    switch (risk) {
      case 'High':
        return red;
      case 'Medium':
        return amber;
      default:
        return teal;
    }
  }

  void updateReview(
    Map<String, dynamic> review,
    String decision,
    BuildContext sheetContext,
  ) {
    if (review['status'] == 'Approved' || review['status'] == 'Rejected') {
      showMessage('This review already has a final decision.');
      return;
    }

    ReviewQueueData.recordDecision(
      review: review,
      decision: decision,
      reason: 'Approved by authorised reviewer.',
    );

    setState(() {});

    Navigator.pop(sheetContext);
    showMessage('Review status updated: $decision');
  }

  Future<void> openReviewDetails(Map<String, dynamic> review) async {
    final decision = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, updateSheet) {
            final status = review['status'] as String;

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: SafeArea(
                child: Column(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Review Details',
                            style: style(size: 19, weight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _detailHeader(review),
                            const SizedBox(height: 16),
                            _detailSection('CONTENT INFORMATION', [
                              _detailRow('Content ID', review['id']),
                              _detailRow('Version', review['version']),
                              _detailRow('Creator', review['creator']),
                              _detailRow('Channel', review['channel']),
                              _detailRow('Submitted', review['date']),
                            ]),
                            const SizedBox(height: 14),
                            _detailSection('INSPECTION SUMMARY', [
                              _detailRow(
                                'Total findings',
                                '${review['findings']}',
                              ),
                              _detailRow('Risk level', review['risk']),
                              _detailRow('Review status', review['status']),
                            ]),
                            if (review['decisionAt'] != null) ...[
                              const SizedBox(height: 14),
                              _detailSection('LATEST DECISION', [
                                _detailRow('Decision', review['status']),
                                _detailRow(
                                  'Reviewer',
                                  (review['decisionBy'] ??
                                          'Authorised Reviewer')
                                      .toString(),
                                ),
                                _detailRow(
                                  'Recorded at',
                                  _formatDecisionTime(
                                    review['decisionAt'].toString(),
                                  ),
                                ),
                                _detailRow(
                                  'Reason',
                                  (review['decisionReason'] ?? '—').toString(),
                                ),
                              ]),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              'CAMPAIGN DESCRIPTION',
                              style: style(
                                size: 10,
                                weight: FontWeight.w800,
                                color: secondary,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: border),
                              ),
                              child: Text(
                                review['description'],
                                style: style(size: 12, color: secondary),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _integrityNotice(),
                            const SizedBox(height: 18),
                          ],
                        ),
                      ),
                    ),
                    if (status == 'Pending' || status == 'Changes Requested')
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 47,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                updateReview(review, 'Approved', sheetContext);
                              },
                              icon: const Icon(
                                Icons.verified_rounded,
                                size: 18,
                              ),
                              label: const Text('Approve Content'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: teal,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.pop(
                                      sheetContext,
                                      'Changes Requested',
                                    );
                                  },
                                  child: const Text('Request Changes'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.pop(sheetContext, 'Rejected');
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: red,
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F5EF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'This item has already received its final decision.',
                          textAlign: TextAlign.center,
                          style: style(
                            size: 11,
                            weight: FontWeight.w700,
                            color: teal,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || decision == null) return;

    if (decision == 'Rejected' || decision == 'Changes Requested') {
      await _showDecisionDialog(review, decision);
    }
  }

  Widget _detailHeader(Map<String, dynamic> review) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(review['id'], style: style(size: 10, color: Colors.white70)),
          const SizedBox(height: 7),
          Text(
            review['title'],
            style: style(
              size: 17,
              weight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusBadge(review['status']),
              const SizedBox(width: 8),
              _riskBadge(review['risk']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: style(size: 10, weight: FontWeight.w800, color: secondary),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: style(size: 11, color: secondary)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style(size: 11, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _integrityNotice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E9F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: navy, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Approval applies to this exact content version only. '
              'Any subsequent edit must invalidate the approval and '
              'trigger a new review.',
              style: style(size: 10, color: navy),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDecisionDialog(
    Map<String, dynamic> review,
    String decision,
  ) async {
    final controller = TextEditingController();

    try {
      final reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              decision,
              style: style(size: 17, weight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    decision == 'Rejected'
                        ? 'Please provide a reason for rejecting this content.'
                        : 'Describe the changes required before approval.',
                    style: style(size: 12, color: secondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Enter decision reason...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final enteredReason = controller.text.trim();

                  if (enteredReason.isEmpty) return;

                  Navigator.pop(dialogContext, enteredReason);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );

      if (!mounted || reason == null || reason.isEmpty) {
        return;
      }

      ReviewQueueData.recordDecision(
        review: review,
        decision: decision,
        reason: reason,
      );

      setState(() {});

      showMessage('$decision recorded successfully.');
    } finally {
      await Future.delayed(const Duration(milliseconds: 350));
      controller.dispose();
    }
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
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeading(),
                    const SizedBox(height: 18),
                    _metrics(),
                    const SizedBox(height: 22),
                    _queueHeading(),
                    const SizedBox(height: 12),
                    _tabs(),
                    const SizedBox(height: 14),
                    if (filteredReviews.isEmpty)
                      _emptyState()
                    else
                      ...filteredReviews.map(_reviewCard),
                    const SizedBox(height: 22),
                    _ledgerSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
              'Review & Approval',
              style: style(size: 16, weight: FontWeight.w800),
            ),
          ),
          const CircleAvatar(
            radius: 17,
            backgroundColor: navy,
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review Queue', style: style(size: 23, weight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text(
          'Verify evidence and make authorised publication decisions.',
          style: style(size: 11, color: secondary),
        ),
      ],
    );
  }

  Widget _metrics() {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'Pending',
            '$pendingCount',
            Icons.pending_actions_rounded,
            amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            'Approved',
            '$approvedCount',
            Icons.verified_rounded,
            teal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricCard(
            'Changes',
            '$changesCount',
            Icons.edit_note_rounded,
            const Color(0xFF66869B),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(height: 9),
          Text(value, style: style(size: 22, weight: FontWeight.w800)),
          Text(title, style: style(size: 9, color: secondary)),
        ],
      ),
    );
  }

  Widget _queueHeading() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Submitted Content',
            style: style(size: 16, weight: FontWeight.w800),
          ),
        ),
        Text(
          '${filteredReviews.length} items',
          style: style(size: 10, color: secondary),
        ),
      ],
    );
  }

  Widget _tabs() {
    final tabs = [
      'Pending',
      'Changes Requested',
      'Approved',
      'Rejected',
      'All',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final active = selectedTab == tab;

          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(tab),
              selected: active,
              onSelected: (_) {
                setState(() => selectedTab = tab);
              },
              selectedColor: navy,
              backgroundColor: Colors.white,
              showCheckmark: false,
              labelStyle: style(
                size: 10,
                weight: FontWeight.w700,
                color: active ? Colors.white : secondary,
              ),
              side: BorderSide(color: active ? navy : border),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    return InkWell(
      onTap: () => openReviewDetails(review),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: navy.withValues(alpha: 0.035),
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
                Expanded(
                  child: Text(
                    review['id'],
                    style: style(size: 9, color: secondary),
                  ),
                ),
                _statusBadge(review['status']),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              review['title'],
              style: style(size: 14, weight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Created by ${review['creator']}',
              style: style(size: 10, color: secondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _smallInfo(Icons.public, review['channel']),
                _smallInfo(Icons.calendar_today_outlined, review['date']),
                _smallInfo(Icons.layers_outlined, review['version']),
              ],
            ),
            const Divider(height: 23, color: border),
            Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: riskColor(review['risk']),
                ),
                const SizedBox(width: 5),
                Text(
                  '${review['risk']} Risk',
                  style: style(
                    size: 10,
                    weight: FontWeight.w700,
                    color: riskColor(review['risk']),
                  ),
                ),
                const SizedBox(width: 13),
                const Icon(
                  Icons.rule_folder_outlined,
                  size: 15,
                  color: secondary,
                ),
                const SizedBox(width: 5),
                Text(
                  '${review['findings']} Findings',
                  style: style(size: 10, color: secondary),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallInfo(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: secondary),
          const SizedBox(width: 5),
          Text(value, style: style(size: 9, color: secondary)),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        status.toUpperCase(),
        style: style(size: 8, weight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _riskBadge(String risk) {
    final color = riskColor(risk);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$risk RISK',
        style: style(size: 8, weight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 36, color: secondary),
          const SizedBox(height: 9),
          Text(
            'No reviews in this category',
            style: style(size: 13, weight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'Submitted content will appear here.',
            style: style(size: 10, color: secondary),
          ),
        ],
      ),
    );
  }

  String _formatDecisionTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year • $hour:$minute';
  }

  Widget _ledgerSection() {
    final completedReviews = reviews.where(
      (item) =>
          item['status'] == 'Approved' ||
          item['status'] == 'Rejected' ||
          item['status'] == 'Changes Requested',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: teal, size: 21),
            const SizedBox(width: 8),
            Text(
              'Approval Ledger',
              style: style(size: 16, weight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'A record of decisions made in this demo session.',
          style: style(size: 10, color: secondary),
        ),
        const SizedBox(height: 12),
        if (completedReviews.isEmpty)
          _emptyState()
        else
          ...completedReviews.map(
            (review) => Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Icon(
                    review['status'] == 'Approved'
                        ? Icons.verified_rounded
                        : review['status'] == 'Rejected'
                        ? Icons.cancel_outlined
                        : Icons.edit_note_rounded,
                    color: statusColor(review['status']),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review['title'],
                          style: style(size: 11, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${review['id']} • ${review['version']}',
                          style: style(size: 9, color: secondary),
                        ),
                        if (review['decisionBy'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Reviewer: ${review['decisionBy']}',
                            style: style(size: 9, color: secondary),
                          ),
                        ],
                        if (review['decisionAt'] != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Recorded: ${_formatDecisionTime(review['decisionAt'].toString())}',
                            style: style(size: 9, color: secondary),
                          ),
                        ],
                        if (review['decisionReason'] != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Reason: ${review['decisionReason']}',
                            style: style(size: 9, color: secondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusBadge(review['status']),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        _ledgerNotice(),
      ],
    );
  }

  Widget _ledgerNotice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: navy, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demo limitation: decision details are stored in memory only. '
              'Production audit records should be append-only, '
              'tamper-evident and server-backed.',
              style: style(size: 10, color: navy),
            ),
          ),
        ],
      ),
    );
  }
}
