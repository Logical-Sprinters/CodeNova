import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:material_ui/material_ui.dart';

import '../features/approvals/approval_verification_screen.dart';
import '../features/receipts/receipt_detail_screen.dart';
import '../features/splash/splash_screen.dart';
import 'app_theme.dart';

class BrandGuardApp extends StatelessWidget {
  const BrandGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      home: const SplashScreen(),
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
