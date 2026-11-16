import 'package:material_ui/material_ui.dart';

import '../../core/network/brandguard_api_service.dart';
import '../../core/auth/session.dart';

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

  List<Map<String, dynamic>> _backendReviews = [];
  bool isLoading = true;
  String? loadError;

  List<Map<String, dynamic>> get reviews => _backendReviews;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final result = await BrandGuardApiService.getReviews();

      final List<dynamic> records = result['reviews'] ?? [];

      final mappedReviews = records.map((item) {
        final review = Map<String, dynamic>.from(item);

        final findings = (review['findings'] as List?) ?? [];

        final createdAt = DateTime.tryParse(
          review['created_at']?.toString() ?? '',
        );

        final severityLevels = findings
            .map((f) => f['severity']?.toString().toLowerCase())
            .toList();

        final risk =
            severityLevels.contains('critical') ||
                severityLevels.contains('review')
            ? 'High'
            : severityLevels.isNotEmpty
            ? 'Medium'
            : 'Low';

        final rawStatus = review['status']?.toString() ?? 'pending';

        return <String, dynamic>{
          'id': review['check_id']?.toString() ?? '',
          'title': '${review['brand_name'] ?? 'Unknown'} Brand Check',
          'creator': review['creator_id']?.toString() ?? 'Unknown',
          'channel': 'Text',
          'date': createdAt == null
              ? 'Unknown'
              : '${createdAt.day.toString().padLeft(2, '0')} '
                    '${createdAt.month.toString().padLeft(2, '0')} '
                    '${createdAt.year}',
          'status': rawStatus == 'approved'
              ? 'Approved'
              : rawStatus == 'rejected'
              ? 'Rejected'
              : rawStatus == 'pending_review' || rawStatus == 'pending'
              ? 'Pending'
              : rawStatus == 'completed'
              ? 'Completed'
              : 'Pending',
          'findings': findings.length,
          'version': 'v${review['content_version'] ?? 1}',
          'contentVersion': review['content_version'] as int?,
          'creatorId': review['creator_id'],
          'contentText': review['content']?.toString() ?? '',
          'rulesVersion': review['rules_version']?.toString() ?? 'Base rules',
          'risk': risk,
          'description':
              'Automated brand compliance check for ${review['brand_name']}. '
              'This review contains ${findings.length} detected findings.',
          'decisionBy': review['reviewer'],
          'decisionReason': review['review_note'],
          'decisionAt': review['decided_at'],
          'contentHash': review['content_hash'],
          'backendFindings': findings,
          'brandName': review['brand_name']?.toString() ?? '',
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _backendReviews = mappedReviews;
        isLoading = false;
        loadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = e.toString();
      });
    }
  }

  TextStyle style({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = navy,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
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

  int get rejectedCount =>
      reviews.where((item) => item['status'] == 'Rejected').length;

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

  Future<void> updateReview(
    Map<String, dynamic> review,
    String decision,
    BuildContext sheetContext,
  ) async {
    if (review['status'] == 'Approved' || review['status'] == 'Rejected') {
      showMessage('This review already has a final decision.');
      return;
    }

    final backendDecision = decision == 'Approved' ? 'approved' : 'rejected';

    try {
      await BrandGuardApiService.decideReview(
        checkId: review['id'].toString(),
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: decision == 'Approved'
            ? 'Approved by authorised reviewer.'
            : 'Rejected by authorised reviewer.',
      );

      if (!mounted || !sheetContext.mounted) return;

      Navigator.pop(sheetContext);

      await _loadReviews();

      showMessage('Review status updated: $decision');
    } catch (e) {
      showMessage('Unable to update review: $e');
    }
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
                              _detailRow('Content version', review['version']),
                              _detailRow(
                                'Rules version',
                                review['rulesVersion'],
                              ),
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
                              'SUBMITTED CONTENT',
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
                                (review['contentText'] as String).isNotEmpty
                                    ? review['contentText']
                                    : review['description'],
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
                    if ((status == 'Pending' ||
                            status == 'Changes Requested') &&
                        (session.currentUser?.isReviewer ?? false) &&
                        review['creatorId'] != session.userId)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 47,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                await updateReview(
                                  review,
                                  'Approved',
                                  sheetContext,
                                );
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
                          status == 'Pending'
                              ? 'Only a separate reviewer can decide this submission.'
                              : 'This item has already received its final decision.',
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
                onPressed: () => Navigator.pop(dialogContext),
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

      if (!mounted || reason == null || reason.isEmpty) return;

      // The current backend supports approved and rejected decisions.
      const backendDecision = 'rejected';

      final backendReason = decision == 'Changes Requested'
          ? 'Changes requested: $reason'
          : reason;

      await BrandGuardApiService.decideReview(
        checkId: review['id'].toString(),
        expectedVersion: review['contentVersion'] as int?,
        decision: backendDecision,
        note: backendReason,
      );

      if (!mounted) return;

      await _loadReviews();

      if (!mounted) return;

      showMessage('$decision recorded successfully.');
    } catch (e) {
      if (!mounted) return;

      showMessage('Unable to record decision: $e');
    } finally {
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
                    if (isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (loadError != null)
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Unable to load reviews',
                              style: style(size: 13, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loadError!,
                              style: style(size: 10, color: red),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _loadReviews,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else if (filteredReviews.isEmpty)
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
            'Rejected',
            '$rejectedCount',
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
    final tabs = ['Pending', 'Approved', 'Rejected', 'All'];

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
          'Decisions returned by the local BrandGuard API.',
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
              'Approval decisions are recorded by the BrandGuard backend. '
              'Each decision is associated with its original content check '
              'and review record.',
              style: style(size: 10, color: navy),
            ),
          ),
        ],
      ),
    );
  }
}
