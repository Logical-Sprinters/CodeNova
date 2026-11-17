import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/approvals/approval_verification_screen.dart';
import '../features/receipts/receipt_detail_screen.dart';
import '../features/splash/splash_screen.dart';
import 'app_theme.dart';
import 'appearance_controller.dart';

class BrandGuardApp extends StatefulWidget {
  const BrandGuardApp({super.key});

  @override
  State<BrandGuardApp> createState() => _BrandGuardAppState();
}

class _BrandGuardAppState extends State<BrandGuardApp>
    with WidgetsBindingObserver {
  static const _preferenceKey = 'brandguard.appearance';

  final _appearance = AppearanceController.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appearance.addListener(_onAppearanceChanged);
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    _appearance.updateSystemBrightness(platformDark);
    unawaited(_restorePreference());
  }

  /// The choice is a device preference, stored on its own — never beside a
  /// token, and never inferred from the account.
  Future<void> _restorePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _appearance.setMode(
        AppearanceController.parse(prefs.getString(_preferenceKey)),
      );
    } catch (_) {
      // A preferences failure must never block startup: stay on `system`.
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _persist(AppearanceMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _preferenceKey,
        AppearanceController.instance.storageValue,
      );
    } catch (_) {
      // Ignored on purpose: the UI already applied the change in memory.
    }
  }

  void _onAppearanceChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_persist(_appearance.mode));
  }

  @override
  void didChangePlatformBrightness() {
    final isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    _appearance.updateSystemBrightness(isDark);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _appearance.removeListener(_onAppearanceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Until the stored preference is read, keep the splash visible so the app
    // never flashes the wrong appearance.
    final themeMode = switch (_appearance.mode) {
      AppearanceMode.light => ThemeMode.light,
      AppearanceMode.dark => ThemeMode.dark,
      AppearanceMode.system => ThemeMode.system,
    };
    final useDark = _appearance.isDark;
    // The palette used by AppTheme.* tokens follows the resolved appearance.
    AppTheme.syncBrightness(useDark ? Brightness.dark : Brightness.light);

    return MaterialApp(
      title: 'BrandGuard',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        flutter_localizations.GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('hi')],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: _ready ? const SplashScreen() : const _AppearanceBootScreen(),
      routes: {
        '/approvalVerification': (_) => const ApprovalVerificationScreen(),
        '/receiptDetail': (context) {
          final receiptId =
              ModalRoute.of(context)!.settings.arguments as String;
          return ReceiptDetailScreen(receiptId: receiptId);
        },
      },
    );
  }
}

/// Neutral first frame while the saved appearance is read from disk.
class _AppearanceBootScreen extends StatelessWidget {
  const _AppearanceBootScreen();

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? AppTheme.navyDeep : AppTheme.background,
      body: Center(
        child: Icon(
          Icons.verified_user_rounded,
          size: 44,
          color: dark ? AppTheme.mintBright : AppTheme.teal,
        ),
      ),
    );
  }
}
