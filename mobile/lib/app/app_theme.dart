import 'package:material_ui/material_ui.dart';

/// BrandGuard "Executive Precision" design tokens.
///
/// Colours and type sizes come from the supplied DESIGN.md so every screen
/// shares one visual language. Nothing here changes application behaviour.
class AppTheme {
  AppTheme._();

  // Brand authority
  static const navy = Color(0xFF142C3B);
  static const navyDeep = Color(0xFF001725);
  static const navyPressed = Color(0xFF20313A);

  // Verification teal family
  static const teal = Color(0xFF22A895);
  static const tealDark = Color(0xFF177F73);
  static const tealText = Color(0xFF006B5E);
  static const mint = Color(0xFFE8F5F1);
  static const mintBright = Color(0xFF81F7E1);

  // Surfaces
  static const background = Color(0xFFF7F8F5);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5ECE9);
  static const surfaceTint = Color(0xFFE8F6FF);

  // Type
  static const ink = Color(0xFF20313A);
  static const inkStrong = Color(0xFF0C1E26);
  static const muted = Color(0xFF78868C);

  // Governance feedback
  static const success = Color(0xFF239B72);
  static const successBg = Color(0xFFE8F5F1);
  static const warning = Color(0xFFE6A23C);
  static const warningBg = Color(0xFFFDF4E4);
  static const danger = Color(0xFFD95D5D);
  static const dangerBg = Color(0xFFFBEFEE);
  static const info = Color(0xFF4A85C5);
  static const infoBg = Color(0xFFEDF4FB);

  /// Tier 1 ambient card shadow.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A142C3B),
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: -2,
    ),
    BoxShadow(color: Color(0x05142C3B), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Tier 2 popover / active inspection shadow.
  static const List<BoxShadow> raisedShadow = [
    BoxShadow(
      color: Color(0x14142C3B),
      blurRadius: 24,
      offset: Offset(0, 10),
      spreadRadius: -4,
    ),
    BoxShadow(color: Color(0x08142C3B), blurRadius: 8, offset: Offset(0, 4)),
  ];

  /// Manrope typography ramp from DESIGN.md.
  static const _font = 'Manrope';

  static TextStyle _t(
    double size,
    FontWeight weight, {
    double height = 1.35,
    double letterSpacing = 0,
    Color color = ink,
  }) => TextStyle(
    fontFamily: _font,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
  );

  static final headlineLarge = _t(
    32,
    FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.64,
    color: inkStrong,
  );
  static final headlineMedium = _t(
    26,
    FontWeight.w700,
    height: 34 / 26,
    letterSpacing: -0.52,
    color: inkStrong,
  );
  static final headlineSmall = _t(
    22,
    FontWeight.w600,
    height: 30 / 22,
    letterSpacing: -0.22,
    color: inkStrong,
  );
  static final titleMedium = _t(18, FontWeight.w600, height: 24 / 18);
  static final bodyLarge = _t(16, FontWeight.w400, height: 24 / 16);
  static final bodyMedium = _t(14, FontWeight.w400, height: 20 / 14);
  static final bodySmall = _t(
    12,
    FontWeight.w400,
    height: 16 / 12,
    letterSpacing: 0.12,
    color: muted,
  );
  static final labelLarge = _t(14, FontWeight.w600, height: 20 / 14);
  static final labelMedium = _t(
    12,
    FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 0.24,
  );
  static final labelSmall = _t(
    10,
    FontWeight.w700,
    height: 14 / 10,
    letterSpacing: 0.5,
  );

  /// Uppercase micro label used for audit metadata.
  static TextStyle monoLabel({Color color = muted}) => _t(
    10,
    FontWeight.w700,
    height: 14 / 10,
    letterSpacing: 0.6,
    color: color,
  );

  /// Tabular figure style for versions, hashes and metrics.
  static TextStyle tabular(
    double size,
    FontWeight weight, {
    Color color = ink,
  }) {
    return _t(
      size,
      weight,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      primary: navy,
      onPrimary: Colors.white,
      secondary: teal,
      onSecondary: Colors.white,
      tertiary: tealDark,
      error: danger,
      surface: card,
      onSurface: ink,
      brightness: Brightness.light,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: _font,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: headlineLarge,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleMedium,
        titleMedium: titleMedium,
        titleSmall: labelLarge,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: inkStrong,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleMedium.copyWith(color: inkStrong),
        iconTheme: const IconThemeData(color: inkStrong, size: 22),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: ink, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: bodyMedium.copyWith(color: muted),
        labelStyle: bodyMedium.copyWith(color: muted),
        floatingLabelStyle: labelMedium.copyWith(color: tealText),
        helperStyle: bodySmall,
        errorStyle: bodySmall.copyWith(color: danger),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          disabledBackgroundColor: navy.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: labelLarge.copyWith(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: card,
          foregroundColor: ink,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: labelLarge,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tealText,
          textStyle: labelLarge,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: mint,
        side: const BorderSide(color: border),
        labelStyle: labelMedium.copyWith(color: ink),
        secondaryLabelStyle: labelMedium.copyWith(color: tealText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: navy,
        contentTextStyle: bodyMedium.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: titleMedium.copyWith(color: inkStrong),
        contentTextStyle: bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: teal,
        linearTrackColor: border,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: tealText,
        textColor: ink,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: muted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? teal : card,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? teal
              : const Color(0xFFD3E5F1),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
