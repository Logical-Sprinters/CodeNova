import 'package:material_ui/material_ui.dart';

/// The single source of truth for the BrandGuard mark inside the app.
///
/// It renders the very same artwork that ships as the platform launcher icon
/// (`assets/images/brandguard_icon.png`), so the in-app logo, the splash mark,
/// the launcher icon and the web favicon can never drift apart.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 48, this.shadow = false});

  /// Rendered width and height in logical pixels.
  final double size;

  /// Adds a soft drop shadow; useful on light backgrounds.
  final bool shadow;

  static const String assetPath = 'assets/images/brandguard_icon.png';

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.225);

    return Container(
      width: size,
      height: size,
      decoration: shadow
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: size * 0.18,
                  offset: Offset(0, size * 0.06),
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          semanticLabel: 'BrandGuard',
        ),
      ),
    );
  }
}
