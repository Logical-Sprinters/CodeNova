import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import 'app_widgets.dart';
import '../../core/auth/session.dart';
import '../../core/network/brandguard_api_service.dart';
import '../../features/dashboard/home_dashboard_screen.dart';
import '../../features/guidelines/guidelines_hub_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reviews/review_queue_screen.dart';
import '../../features/workspace/workspace_hub_screen.dart';

/// Fixed bottom navigation described in DESIGN.md (Tier 3 chrome).
class BrandGuardShell extends StatefulWidget {
  const BrandGuardShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<BrandGuardShell> createState() => _BrandGuardShellState();
}

class _BrandGuardShellState extends State<BrandGuardShell> {
  late int _index = widget.initialIndex;
  int _pending = 0;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refreshBadges();
  }

  /// Best-effort badge counts with one retry. A failure here never blocks
  /// navigation and never shows a spinner.
  Future<void> _refreshBadges() async {
    if (session.accessToken == null) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final results = await Future.wait([
          BrandGuardApiService.getJson('/api/v1/analytics'),
          BrandGuardApiService.getJson('/api/v1/notifications'),
        ]);
        if (!mounted) return;
        setState(() {
          _pending = (results[0]['pending'] as num?)?.toInt() ?? 0;
          _unread = (results[1]['unread'] as num?)?.toInt() ?? 0;
        });
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
  }

  void _select(int value) {
    if (value == _index) return;
    setState(() => _index = value);
    _refreshBadges();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomeDashboardScreen(embedded: true),
      WorkspaceHubScreen(embedded: true),
      ReviewQueueScreen(embedded: true),
      GuidelinesHubScreen(embedded: true),
      ProfileScreen(embedded: true),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        pending: _pending,
        unread: _unread,
        onSelected: _select,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.pending,
    required this.unread,
    required this.onSelected,
  });

  final int index;
  final int pending;
  final int unread;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, IconData, String, int?)>[
      (Icons.home_outlined, Icons.home_rounded, 'Home', null),
      (
        Icons.dashboard_customize_outlined,
        Icons.dashboard_customize_rounded,
        'Workspace',
        null,
      ),
      (
        Icons.fact_check_outlined,
        Icons.fact_check_rounded,
        'Reviews',
        pending > 0 ? pending : null,
      ),
      (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Guidelines', null),
      (Icons.person_outline, Icons.person_rounded, 'Profile', null),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: AppTheme.border)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A142C3B),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BottomItem(
                    item: items[i],
                    selected: index == i,
                    badge: i == 2
                        ? (pending > 0 ? pending : null)
                        : (i == 0 && unread > 0 ? unread : null),
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final (IconData, IconData, String, int?) item;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.teal : AppTheme.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.$3,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(selected ? item.$2 : item.$1, size: 22, color: color),
                    if (badge != null)
                      Positioned(
                        right: -8,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          constraints: const BoxConstraints(minWidth: 15),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$badge',
                            textAlign: TextAlign.center,
                            style: AppTheme.monoLabel(color: Colors.white)
                                .copyWith(fontSize: 9),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.$3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.monoLabel(color: color)
                    .copyWith(fontSize: 9.5, letterSpacing: 0.2),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 16 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.teal,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard in-page header used by every tab (brand mark + role + actions).
class ShellHeader extends StatelessWidget {
  const ShellHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showMark = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final user = session.currentUser;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          if (showMark) ...[
            const BrandMark(size: 38, radius: 11),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle ??
                      (user == null
                          ? 'Pre-publication governance'
                          : '${user.name} · ${user.isReviewer ? "Authorised Reviewer" : "Creator"}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.monoLabel(color: AppTheme.tealText),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Role chip shown on dark headers.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.isReviewer, this.onDark = false});

  final bool isReviewer;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onDark
            ? AppTheme.mintBright.withValues(alpha: 0.14)
            : AppTheme.mint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (onDark ? AppTheme.mintBright : AppTheme.teal).withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReviewer ? Icons.verified_rounded : Icons.edit_note_rounded,
            size: 12,
            color: onDark ? AppTheme.mintBright : AppTheme.tealText,
          ),
          const SizedBox(width: 4),
          Text(
            isReviewer ? 'AUTHORISED REVIEWER' : 'CREATOR',
            style: AppTheme.monoLabel(
              color: onDark ? AppTheme.mintBright : AppTheme.tealText,
            ),
          ),
        ],
      ),
    );
  }
}
