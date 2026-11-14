import 'package:flutter/material.dart';

import '../core/session.dart';
import '../features/audit/ledger_screen.dart';
import '../features/check/new_check_screen.dart';
import '../features/guidelines/guidelines_screen.dart';
import '../features/home/home_screen.dart';
import '../features/review/review_screen.dart';
import '../features/sign_in/sign_in_screen.dart';
import 'theme.dart';

/// One shell, two form factors: bottom navigation on a phone, a rail on a
/// laptop. Nothing else in the app knows which one it is running in.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const List<String> _labels = <String>[
    'Home',
    'New check',
    'Reviews',
    'Ledger',
    'Guidelines',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.home_outlined,
    Icons.add_circle_outline,
    Icons.fact_check_outlined,
    Icons.receipt_long_outlined,
    Icons.menu_book_outlined,
  ];

  List<Widget> get _pages => const <Widget>[
        HomeScreen(),
        NewCheckScreen(),
        ReviewScreen(),
        LedgerScreen(),
        GuidelinesScreen(),
      ];

  void _switchUser() {
    session.signOut();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      title: Text(_labels[_index]),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: PopupMenuButton<String>(
            tooltip: 'Identity',
            onSelected: (String value) {
              if (value == 'switch') _switchUser();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  '${session.user?.name ?? ''} · ${session.user?.role ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Bg.unsupported),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'switch',
                child: Text('Switch identity'),
              ),
            ],
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Text(
                (session.user?.name ?? '?').substring(0, 1),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    final Widget body = IndexedStack(index: _index, children: _pages);

    if (wide) {
      return Scaffold(
        appBar: _appBar(context),
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (int i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Bg.card,
              indicatorColor: Bg.secondary.withAlpha(38),
              selectedIconTheme: const IconThemeData(color: Bg.tertiary),
              destinations: <NavigationRailDestination>[
                for (int i = 0; i < _labels.length; i++)
                  NavigationRailDestination(
                    icon: Icon(_icons[i]),
                    selectedIcon: Icon(_icons[i]),
                    label: Text(_labels[i]),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: Bg.line),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(context),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() => _index = i),
        backgroundColor: Bg.card,
        indicatorColor: Bg.secondary.withAlpha(38),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: <Widget>[
          for (int i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}
