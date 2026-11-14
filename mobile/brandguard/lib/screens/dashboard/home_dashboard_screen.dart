import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../review/review_queue_screen.dart';
import '../workspace/new_brand_check_screen.dart';
import '../workspace/brand_guidelines_screen.dart';
import '../workspace/upload_rule_screen.dart';
import '../workspace/fact_sources_screen.dart';
import '../workspace/workspace_hub_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import 'admin_analytics_screen.dart';

class DashboardColors {
  static const navy = Color(0xFF142C3B);
  static const darkNavy = Color(0xFF001725);
  static const teal = Color(0xFF006B5E);
  static const brightTeal = Color(0xFF22A895);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF7F8F6);
  static const lightBlue = Color(0xFFE8F6FF);
  static const border = Color(0xFFE5EAE7);
  static const text = Color(0xFF26363C);
  static const secondary = Color(0xFF73787C);
  static const red = Color(0xFFC96B6B);
  static const amber = Color(0xFFB98742);
  static const green = Color(0xFF4B9475);
}

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _selectedTab = 0;
  int unreadNotifications = 0;
  String displayName = 'Elena Jordan';

  static const String _notificationsStorageKey =
      'brandguard_notifications_v2';

  @override
  void initState() {
    super.initState();

    ReviewQueueData.initialize().then((_) {
      if (mounted) setState(() {});
    });

    _refreshDashboardUserData();
  }

  Future<void> _refreshDashboardUserData() async {
    final prefs = await SharedPreferences.getInstance();

    final savedName =
        prefs.getString('bg_profile_name') ?? 'Elena Jordan';

    final savedNotifications =
        prefs.getString(_notificationsStorageKey);

    var unread = 0;

    if (savedNotifications != null) {
      try {
        final decoded = jsonDecode(savedNotifications) as List;

        unread = decoded.where((item) {
          return item is Map && item['read'] == false;
        }).length;
      } catch (_) {
        unread = 0;
      }
    }

    if (!mounted) return;

    setState(() {
      displayName = savedName;
      unreadNotifications = unread;
    });
  }

  Future<void> _openNewBrandCheck() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewBrandCheckScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openReviewQueue() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReviewQueueScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openGuidelines() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BrandGuidelinesScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openUploadRule() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UploadRuleScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openFactSources() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FactSourcesScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openAnalytics() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminAnalyticsScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openWorkspace() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WorkspaceHubScreen(),
      ),
    );

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );

    if (!mounted) return;
    await _refreshDashboardUserData();
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
      ),
    );

    if (!mounted) return;
    await _refreshDashboardUserData();
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);

    if (index == 1) {
      _openWorkspace();
    } else if (index == 2) {
      _openReviewQueue();
    } else if (index == 3) {
      _openGuidelines();
    } else if (index == 4) {
      _openAnalytics();
    }

    if (index != 0 && mounted) {
      setState(() => _selectedTab = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _welcomeSection(),
                    const SizedBox(height: 20),
                    _newCheckButton(),
                    const SizedBox(height: 20),
                    _metricsGrid(),
                    const SizedBox(height: 22),
                    _quickActions(),
                    const SizedBox(height: 22),
                    _recentActivity(),
                    const SizedBox(height: 18),
                    _integrityBanner(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNavigation(),
    );
  }

  Widget _header() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: DashboardColors.background.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: DashboardColors.navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: DashboardColors.darkNavy,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: DashboardColors.brightTeal,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'BrandGuard',
                    style: _style(
                      size: 17,
                      weight: FontWeight.w800,
                      color: DashboardColors.darkNavy,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.circle,
                    size: 7,
                    color: DashboardColors.teal,
                  ),
                ],
              ),
              Text(
                'Home',
                style: _style(
                  size: 10,
                  weight: FontWeight.w600,
                  color: DashboardColors.secondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: DashboardColors.secondary,
                  size: 24,
                ),
                if (unreadNotifications > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: DashboardColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _openProfile,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: DashboardColors.darkNavy,
              child: Text(
                _initials(displayName),
                style: _style(
                  size: 10,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFDDEFEA),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: DashboardColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'GOVERNANCE ENGINE ACTIVE • V2.4.1',
                    style: _style(
                      size: 9,
                      weight: FontWeight.w800,
                      color: DashboardColors.teal,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.verified_user_rounded,
              size: 15,
              color: DashboardColors.teal,
            ),
            const SizedBox(width: 4),
            Text(
              'Secure',
              style: _style(
                size: 10,
                weight: FontWeight.w700,
                color: DashboardColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Good morning, ${displayName.split(' ').first}',
          style: _style(
            size: 25,
            weight: FontWeight.w800,
            color: DashboardColors.darkNavy,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Let's keep your brand protected and compliant.",
          style: _style(
            size: 12,
            color: DashboardColors.secondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
    Widget _newCheckButton() {
    return SizedBox(
      height: 49,
      child: ElevatedButton.icon(
        onPressed: _openNewBrandCheck,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
        label: Text(
          'New Brand Check',
          style: _style(
            size: 13,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: DashboardColors.navy,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _metricsGrid() {
    final allReviews = ReviewQueueData.reviews;
    final totalChecks = allReviews.length;

    final pending =
        allReviews.where((item) => item['status'] == 'Pending').length;

    final approved =
        allReviews.where((item) => item['status'] == 'Approved').length;

    final totalFindings = allReviews.fold<int>(
      0,
      (total, item) => total + ((item['findings'] as int?) ?? 0),
    );

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 11,
      mainAxisSpacing: 11,
      childAspectRatio: 1.48,
      children: [
        _metricCard(
          'TOTAL CHECKS',
          '$totalChecks',
          'All submitted content',
          Icons.folder_open_rounded,
          DashboardColors.navy,
          DashboardColors.lightBlue,
        ),
        _metricCard(
          'PENDING',
          '$pending',
          'Awaiting authorised review',
          Icons.schedule_rounded,
          DashboardColors.amber,
          const Color(0xFFFBF4E8),
          tag: pending > 0 ? 'Action' : null,
        ),
        _metricCard(
          'APPROVED',
          '$approved',
          'Authorised content',
          Icons.check_circle_rounded,
          DashboardColors.green,
          const Color(0xFFEAF4EE),
        ),
        _metricCard(
          'FINDINGS',
          '$totalFindings',
          'Across submitted content',
          Icons.warning_amber_rounded,
          DashboardColors.red,
          const Color(0xFFFBEFEE),
        ),
      ],
    );
  }

  Widget _metricCard(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color accent,
    Color tint, {
    String? tag,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashboardColors.border),
        boxShadow: [
          BoxShadow(
            color: DashboardColors.navy.withValues(alpha: 0.025),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(
                    size: 9,
                    weight: FontWeight.w800,
                    color: DashboardColors.secondary,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: accent, size: 17),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: _style(
                  size: 25,
                  weight: FontWeight.w800,
                  color: DashboardColors.text,
                  letterSpacing: -0.7,
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 7),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: _style(
                        size: 8,
                        weight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(
              size: 9,
              weight: FontWeight.w600,
              color: accent == DashboardColors.navy
                  ? DashboardColors.teal
                  : DashboardColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Fast Actions',
              style: _style(
                size: 16,
                weight: FontWeight.w800,
                color: DashboardColors.text,
              ),
            ),
            const Spacer(),
            Text(
              'SHORTCUTS',
              style: _style(
                size: 9,
                weight: FontWeight.w800,
                color: DashboardColors.teal,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _actionTile(
                'Review Queue',
                Icons.assignment_turned_in_rounded,
                const Color(0xFFDDF3ED),
                DashboardColors.teal,
                _openReviewQueue,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _actionTile(
                'Upload Rule',
                Icons.upload_file_rounded,
                DashboardColors.lightBlue,
                DashboardColors.navy,
                _openUploadRule,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _actionTile(
                'Fact Sources',
                Icons.storage_rounded,
                const Color(0xFFDDE8EF),
                DashboardColors.navy,
                _openFactSources,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionTile(
    String title,
    IconData icon,
    Color tint,
    Color accent,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 94,
          padding: const EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: DashboardColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 19),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(
                  size: 9,
                  weight: FontWeight.w800,
                  color: DashboardColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentActivity() {
    final recentReviews =
        ReviewQueueData.reviews.reversed.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent Activity',
              style: _style(
                size: 16,
                weight: FontWeight.w800,
                color: DashboardColors.text,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: DashboardColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${ReviewQueueData.reviews.length}',
                style: _style(
                  size: 9,
                  weight: FontWeight.w800,
                  color: DashboardColors.secondary,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openReviewQueue,
              style: TextButton.styleFrom(
                foregroundColor: DashboardColors.teal,
                padding: EdgeInsets.zero,
              ),
              iconAlignment: IconAlignment.end,
              label: Text(
                'View all (${ReviewQueueData.reviews.length})',
                style: _style(
                  size: 10,
                  weight: FontWeight.w800,
                  color: DashboardColors.teal,
                ),
              ),
              icon: const Icon(
                Icons.chevron_right_rounded,
                size: 17,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (recentReviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: DashboardColors.border),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.inbox_outlined,
                  size: 30,
                  color: DashboardColors.secondary,
                ),
                const SizedBox(height: 8),
                Text(
                  'No recent activity yet',
                  style: _style(
                    size: 12,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your submitted brand checks will appear here.',
                  textAlign: TextAlign.center,
                  style: _style(
                    size: 10,
                    color: DashboardColors.secondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...recentReviews.map((review) {
            final title =
                (review['title'] ?? 'Untitled Submission').toString();

            final creator =
                (review['creator'] ?? 'Unknown Creator').toString();

            final channel =
                (review['channel'] ?? 'General').toString();

            final status =
                (review['status'] ?? 'Pending').toString();

            final version =
                (review['version'] ?? 'v1.0').toString();

            final risk =
                (review['risk'] ?? 'Unspecified').toString();

            final findings =
                (review['findings'] as num?)?.toInt() ?? 0;

            final reviewId = (review['id'] ?? '').toString();

            final description =
                (review['description'] ?? '').toString();

            Color statusColor;
            Color statusTint;

            switch (status) {
              case 'Approved':
                statusColor = DashboardColors.green;
                statusTint = const Color(0xFFEAF4EE);
                break;

              case 'Changes Requested':
                statusColor = DashboardColors.amber;
                statusTint = const Color(0xFFFBF4E8);
                break;

              case 'Rejected':
                statusColor = DashboardColors.red;
                statusTint = const Color(0xFFFBEFEE);
                break;

              default:
                statusColor = DashboardColors.navy;
                statusTint = DashboardColors.lightBlue;
            }

            final initials = creator
                .trim()
                .split(RegExp(r'\s+'))
                .where((part) => part.isNotEmpty)
                .take(2)
                .map((part) => part[0].toUpperCase())
                .join();

            final message = description.isNotEmpty
                ? description
                : '$findings findings • $version • $risk Risk';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _activityCard(
                title: title,
                subtitle: '$channel • $reviewId',
                status: status.toUpperCase(),
                statusColor: statusColor,
                statusTint: statusTint,
                message: message,
                messageColor: statusTint,
                person: initials.isEmpty ? 'U' : initials,
                personName: creator,
                action: '$findings Findings • $version',
              ),
            );
          }),
      ],
    );
  }
    Widget _activityCard({
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required Color statusTint,
    required String message,
    required Color messageColor,
    required String person,
    required String personName,
    required String action,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashboardColors.border),
        boxShadow: [
          BoxShadow(
            color: DashboardColors.navy.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        size: 12,
                        weight: FontWeight.w800,
                        color: DashboardColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        size: 9,
                        color: DashboardColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusTint,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  status,
                  style: _style(
                    size: 8,
                    weight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: messageColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              message,
              style: _style(
                size: 9,
                color: DashboardColors.secondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: DashboardColors.navy,
                child: Text(
                  person,
                  style: _style(
                    size: 8,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  personName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(
                    size: 9,
                    weight: FontWeight.w600,
                    color: DashboardColors.text,
                  ),
                ),
              ),
              Text(
                action,
                style: _style(
                  size: 9,
                  weight: FontWeight.w700,
                  color: DashboardColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _integrityBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F0F4),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: DashboardColors.teal,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Core Integrity Charter',
                  style: _style(
                    size: 11,
                    weight: FontWeight.w800,
                    color: DashboardColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '“No finding without evidence. No approval without a version.”',
                  style: _style(
                    size: 9,
                    color: DashboardColors.secondary,
                    height: 1.45,
                    italic: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: DashboardColors.navy.withValues(alpha: 0.06),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 63,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final selected = _selectedTab == index;

              return InkWell(
                onTap: () => _selectTab(index),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 65,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFDDF3ED)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          tab.icon,
                          size: 20,
                          color: selected
                              ? DashboardColors.teal
                              : DashboardColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: _style(
                          size: 8,
                          weight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? DashboardColors.teal
                              : DashboardColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();

    if (parts.isEmpty) return 'U';

    return parts.map((part) => part[0].toUpperCase()).join();
  }

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = DashboardColors.text,
    double? height,
    double letterSpacing = 0,
    bool italic = false,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );
  }
}

class _DashboardTab {
  const _DashboardTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

const List<_DashboardTab> _tabs = [
  _DashboardTab('Home', Icons.home_rounded),
  _DashboardTab('Workspace', Icons.layers_rounded),
  _DashboardTab('Reviews', Icons.verified_rounded),
  _DashboardTab('Guidelines', Icons.menu_book_rounded),
  _DashboardTab('Analytics', Icons.analytics_rounded),
];