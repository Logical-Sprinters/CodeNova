import 'package:material_ui/material_ui.dart';

/// Shared app/splash palette and the root Material theme.
class AppTheme {
  AppTheme._();

  static const navy = Color(0xFF142C3B);
  static const teal = Color(0xFF22A895);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF7F8F5);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    fontFamily: 'Manrope',
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      primary: navy,
      secondary: teal,
    ),
  );
}
