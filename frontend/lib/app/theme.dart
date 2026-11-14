import 'package:flutter/material.dart';

/// Executive Precision. Every value comes from ../../design/tokens.json.
///
/// Rule for this codebase: no colour literal outside this file. If a colour is
/// needed somewhere else, it belongs here first.
class Bg {
  static const Color primary = Color(0xFF142C3B);    // navy — bars, headings
  static const Color secondary = Color(0xFF22A895);  // teal — the one accent
  static const Color tertiary = Color(0xFF177F73);   // deep teal — active state
  static const Color ink = Color(0xFF20313A);        // body text
  static const Color surface = Color(0xFFF7F9FA);    // page
  static const Color card = Colors.white;
  static const Color line = Color(0xFFE2E8EC);

  // The five finding statuses, mirroring finding_status in the database.
  static const Color confirmed = Color(0xFFC0392B);
  static const Color interpretation = Color(0xFFB7791F);
  static const Color unsupported = Color(0xFF5A6B75); // never red
  static const Color conflict = Color(0xFFC05621);
  static const Color human = Color(0xFF6B46C1);

  static const Color approved = Color(0xFF1E7B4F);
  static const Color voided = Color(0xFF8A94A0);
}

const double kRailBreakpoint = 720;
const double kMaxContentWidth = 900;
const double kTouchTarget = 52;

ThemeData buildTheme() {
  final ThemeData base = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Bg.surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Bg.primary,
      primary: Bg.primary,
      secondary: Bg.secondary,
      surface: Bg.surface,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Manrope',
      bodyColor: Bg.ink,
      displayColor: Bg.primary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Bg.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Bg.secondary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, kTouchTarget),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Bg.primary,
        minimumSize: const Size(0, kTouchTarget),
        side: const BorderSide(color: Bg.line),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Bg.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Bg.secondary),
      ),
    ),
  );
}

/// The five statuses in one place, so the same fact never looks different on
/// two screens. The database decides these; the app only renders them.
class StatusStyle {
  const StatusStyle._();

  static Color colour(String status) {
    switch (status) {
      case 'CONFIRMED_RULE_MATCH':
        return Bg.confirmed;
      case 'AI_INTERPRETATION':
        return Bg.interpretation;
      case 'SOURCE_CONFLICT_OR_EXPIRED':
        return Bg.conflict;
      case 'NEEDS_AUTHORISED_REVIEWER':
        return Bg.human;
      case 'APPROVED':
        return Bg.approved;
      case 'VOID':
        return Bg.voided;
      default:
        return Bg.unsupported;
    }
  }

  static String label(String status) {
    switch (status) {
      case 'CONFIRMED_RULE_MATCH':
        return 'Confirmed rule match';
      case 'AI_INTERPRETATION':
        return 'Interpretation';
      case 'UNSUPPORTED':
        return 'Unsupported';
      case 'SOURCE_CONFLICT_OR_EXPIRED':
        return 'Source conflict';
      case 'NEEDS_AUTHORISED_REVIEWER':
        return 'Needs a reviewer';
      case 'APPROVED':
        return 'Approved';
      case 'VOID':
        return 'Void';
      case 'DRAFT':
        return 'Draft';
      default:
        return status;
    }
  }

  static bool blocksApproval(String status) =>
      status == 'CONFIRMED_RULE_MATCH' || status == 'SOURCE_CONFLICT_OR_EXPIRED';
}
