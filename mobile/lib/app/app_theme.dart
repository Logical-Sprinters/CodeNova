import 'package:material_ui/material_ui.dart';

/// BrandGuard "Executive Precision" design tokens.
///
/// Colours and type sizes come from the supplied DESIGN.md so every screen
/// shares one visual language. Nothing here changes application behaviour.
class AppTheme {
  AppTheme._();

  // Brand authority (shared by both appearances)
  static const navy = Color(0xFF142C3B);
  static const navyDeep = Color(0xFF001725);
  static const navyPressed = Color(0xFF20313A);

  // Verification teal family
  static const teal = Color(0xFF22A895);
  static const tealDark = Color(0xFF177F73);
  static const mintBright = Color(0xFF81F7E1);

  /// Brightness of the active theme, refreshed by [BrandGuardApp] on every
  /// build so a plain static token (`AppTheme.ink`) always resolves correctly.
  static bool _isDark = false;

  static _Palette get _current => _isDark ? _dark : _light;

  /// Called from the MaterialApp builder, which runs above every screen.
  static void syncBrightness(Brightness brightness) {
    _isDark = brightness == Brightness.dark;
  }

  /// Registers a dependency on the ambient theme and syncs the palette.
  ///
  /// Every `build` calls this exactly once. The dependency is what makes a
  /// light -> dark switch actually repaint: without it Flutter skips widgets
  /// (especially `const` ones) and they would keep painting the old palette.
  static Brightness watch(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    _isDark = brightness == Brightness.dark;
    return brightness;
  }

  /// Test-only escape hatch so widget tests can pin an appearance.
  @visibleForTesting
  static void debugSetBrightness(Brightness brightness) {
    _isDark = brightness == Brightness.dark;
  }

  static Color get background => _current.background;
  static Color get card => _current.card;
  static Color get cardAlt => _current.cardAlt;
  static Color get border => _current.border;
  static Color get borderStrong => _current.borderStrong;
  static Color get surfaceTint => _current.surfaceTint;
  static Color get ink => _current.ink;
  static Color get inkStrong => _current.inkStrong;
  static Color get muted => _current.muted;
  static Color get mint => _current.mint;
  static Color get tealText => _current.tealText;
  static Color get success => _current.success;
  static Color get successBg => _current.successBg;
  static Color get warning => _current.warning;
  static Color get warningBg => _current.warningBg;
  static Color get danger => _current.danger;
  static Color get dangerBg => _current.dangerBg;
  static Color get info => _current.info;
  static Color get infoBg => _current.infoBg;
  static Color get neutralBg => _current.neutralBg;
  static List<BoxShadow> get cardShadow => _current.cardShadow;
  static List<BoxShadow> get raisedShadow => _current.raisedShadow;

  static const _light = _Palette(
    background: Color(0xFFF7F8F5),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF2F5F4),
    border: Color(0xFFE5ECE9),
    borderStrong: Color(0xFFD3DDD9),
    surfaceTint: Color(0xFFE8F6FF),
    ink: Color(0xFF20313A),
    inkStrong: Color(0xFF0C1E26),
    muted: Color(0xFF78868C),
    mint: Color(0xFFE8F5F1),
    tealText: Color(0xFF006B5E),
    success: Color(0xFF239B72),
    successBg: Color(0xFFE8F5F1),
    warning: Color(0xFFE6A23C),
    warningBg: Color(0xFFFDF4E4),
    danger: Color(0xFFD95D5D),
    dangerBg: Color(0xFFFBEFEE),
    info: Color(0xFF4A85C5),
    infoBg: Color(0xFFEDF4FB),
    neutralBg: Color(0xFFF2F5F4),
    cardShadow: [
      BoxShadow(
        color: Color(0x0A142C3B),
        blurRadius: 8,
        offset: Offset(0, 2),
        spreadRadius: -2,
      ),
      BoxShadow(color: Color(0x05142C3B), blurRadius: 4, offset: Offset(0, 1)),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x14142C3B),
        blurRadius: 24,
        offset: Offset(0, 10),
        spreadRadius: -4,
      ),
      BoxShadow(color: Color(0x08142C3B), blurRadius: 8, offset: Offset(0, 4)),
    ],
  );

  /// Deep navy surfaces with the same teal verification language. Feedback
  /// colours are lifted (lighter fg, darker tinted bg) so they stay legible on
  /// dark cards instead of glowing or disappearing.
  static const _dark = _Palette(
    background: Color(0xFF0B1620),
    card: Color(0xFF122330),
    cardAlt: Color(0xFF172B3A),
    border: Color(0xFF23394A),
    borderStrong: Color(0xFF2F4A5E),
    surfaceTint: Color(0xFF16293A),
    ink: Color(0xFFE4EDF1),
    inkStrong: Color(0xFFF4F9FB),
    muted: Color(0xFF9BAEB8),
    mint: Color(0xFF16303A),
    tealText: Color(0xFF7FE3D2),
    success: Color(0xFF5FD2A6),
    successBg: Color(0xFF122F2A),
    warning: Color(0xFFF0BE6B),
    warningBg: Color(0xFF32280F),
    danger: Color(0xFFF08D8D),
    dangerBg: Color(0xFF33191A),
    info: Color(0xFF8DBDF0),
    infoBg: Color(0xFF152A40),
    neutralBg: Color(0xFF1B2E3B),
    cardShadow: [
      BoxShadow(
        color: Color(0x40000000),
        blurRadius: 10,
        offset: Offset(0, 3),
        spreadRadius: -2,
      ),
      BoxShadow(color: Color(0x26000000), blurRadius: 5, offset: Offset(0, 1)),
    ],
    raisedShadow: [
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 26,
        offset: Offset(0, 12),
        spreadRadius: -4,
      ),
      BoxShadow(color: Color(0x33000000), blurRadius: 9, offset: Offset(0, 4)),
    ],
  );

  /// Manrope typography ramp from DESIGN.md.
  static const _font = 'Manrope';

  static TextStyle _t(
    double size,
    FontWeight weight, {
    double height = 1.35,
    double letterSpacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: _font,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? ink,
  );

  static TextStyle get headlineLarge => _t(
    32,
    FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.64,
    color: inkStrong,
  );
  static TextStyle get headlineMedium => _t(
    26,
    FontWeight.w700,
    height: 34 / 26,
    letterSpacing: -0.52,
    color: inkStrong,
  );
  static TextStyle get headlineSmall => _t(
    22,
    FontWeight.w600,
    height: 30 / 22,
    letterSpacing: -0.22,
    color: inkStrong,
  );
  static TextStyle get titleMedium => _t(18, FontWeight.w600, height: 24 / 18);
  static TextStyle get bodyLarge => _t(16, FontWeight.w400, height: 24 / 16);
  static TextStyle get bodyMedium => _t(14, FontWeight.w400, height: 20 / 14);
  static TextStyle get bodySmall => _t(
    12,
    FontWeight.w400,
    height: 16 / 12,
    letterSpacing: 0.12,
    color: muted,
  );
  static TextStyle get labelLarge => _t(14, FontWeight.w600, height: 20 / 14);
  static TextStyle get labelMedium =>
      _t(12, FontWeight.w600, height: 16 / 12, letterSpacing: 0.24);
  static TextStyle get labelSmall =>
      _t(10, FontWeight.w700, height: 14 / 10, letterSpacing: 0.5);

  /// Uppercase micro label used for audit metadata.
  static TextStyle monoLabel({Color? color}) => _t(
    10,
    FontWeight.w700,
    height: 14 / 10,
    letterSpacing: 0.6,
    color: color ?? muted,
  );

  /// Tabular figure style for versions, hashes and metrics.
  static TextStyle tabular(double size, FontWeight weight, {Color? color}) {
    return _t(
      size,
      weight,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  /// One builder for both appearances: the light palette is the reference and
  /// the dark palette only swaps resolved colours, so spacing, type and shape
  /// can never drift between themes.
  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final palette = dark ? _dark : _light;

    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      primary: dark ? palette.tealText : navy,
      onPrimary: dark ? navyDeep : Colors.white,
      secondary: teal,
      onSecondary: dark ? navyDeep : Colors.white,
      tertiary: palette.tealText,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.card,
      onSurface: palette.ink,
      brightness: brightness,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: _font,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
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
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.inkStrong,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: titleMedium.copyWith(color: palette.inkStrong),
        iconTheme: IconThemeData(color: palette.inkStrong, size: 22),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: palette.ink, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? palette.cardAlt : palette.card,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: bodyMedium.copyWith(color: palette.muted),
        labelStyle: bodyMedium.copyWith(color: palette.muted),
        floatingLabelStyle: labelMedium.copyWith(color: palette.tealText),
        helperStyle: bodySmall,
        errorStyle: bodySmall.copyWith(color: palette.danger),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? palette.tealText : navy,
          foregroundColor: dark ? navyDeep : Colors.white,
          disabledBackgroundColor: (dark ? palette.tealText : navy).withValues(
            alpha: 0.35,
          ),
          disabledForegroundColor: dark ? palette.muted : Colors.white70,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: labelLarge.copyWith(color: dark ? navyDeep : Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: dark ? palette.cardAlt : palette.card,
          foregroundColor: palette.ink,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: labelLarge.copyWith(color: palette.ink),
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.tealText,
          textStyle: labelLarge.copyWith(color: palette.tealText),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: dark ? palette.cardAlt : palette.card,
        selectedColor: palette.mint,
        side: BorderSide(color: palette.border),
        labelStyle: labelMedium.copyWith(color: palette.ink),
        secondaryLabelStyle: labelMedium.copyWith(color: palette.tealText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? palette.cardAlt : navy,
        contentTextStyle: bodyMedium.copyWith(
          color: dark ? palette.ink : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: titleMedium.copyWith(color: palette.inkStrong),
        contentTextStyle: bodyMedium.copyWith(color: palette.ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: dark ? navyDeep : Colors.white,
        elevation: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: teal,
        linearTrackColor: palette.border,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.tealText,
        textColor: palette.ink,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: palette.muted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? teal : palette.card,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? teal
              : (dark ? palette.borderStrong : const Color(0xFFD3E5F1)),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}

/// Immutable colour set for one appearance.
class _Palette {
  const _Palette({
    required this.background,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.borderStrong,
    required this.surfaceTint,
    required this.ink,
    required this.inkStrong,
    required this.muted,
    required this.mint,
    required this.tealText,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.neutralBg,
    required this.cardShadow,
    required this.raisedShadow,
  });

  final Color background;
  final Color card;
  final Color cardAlt;
  final Color border;
  final Color borderStrong;
  final Color surfaceTint;
  final Color ink;
  final Color inkStrong;
  final Color muted;
  final Color mint;
  final Color tealText;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color danger;
  final Color dangerBg;
  final Color info;
  final Color infoBg;
  final Color neutralBg;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> raisedShadow;
}
