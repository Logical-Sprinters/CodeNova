import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../auth/sign_in_screen.dart';

/// Branded splash. It performs no network calls and no security claims beyond
/// describing the governance engine that powers the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _progress;
  late final AnimationController _orbit;
  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  String _step = 'CONNECTING TO GOVERNANCE ENGINE';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _step = 'VERIFYING GOVERNANCE ENGINE');
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _progress.dispose();
    _orbit.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.9,
                  colors: [
                    const Color(0xFF16394A),
                    AppTheme.navyDeep.withValues(alpha: 0.98),
                    const Color(0xFF04141C),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -80,
            child: _glow(280, AppTheme.teal.withValues(alpha: 0.22)),
          ),
          Positioned(
            bottom: -110,
            right: -70,
            child: _glow(260, AppTheme.mintBright.withValues(alpha: 0.1)),
          ),
          const Positioned.fill(child: CustomPaint(painter: GridPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _chip(
                        'VAULT SECURE',
                        dot: AppTheme.mintBright,
                        onDark: true,
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: AppTheme.mintBright,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'SESSION TOKENS IN MEMORY',
                            style: AppTheme.monoLabel(
                              color: AppTheme.mintBright,
                            ).copyWith(fontSize: 9),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, child) => Transform.scale(
                              scale: 1 + _pulse.value * 0.03,
                              child: child,
                            ),
                            child: SizedBox(
                              width: 190,
                              height: 190,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _orbit,
                                    builder: (context, child) =>
                                        Transform.rotate(
                                          angle: _orbit.value * 2 * math.pi,
                                          child: child,
                                        ),
                                    child: CustomPaint(
                                      size: const Size(190, 190),
                                      painter: OrbitPainter(),
                                    ),
                                  ),
                                  Container(
                                    width: 124,
                                    height: 124,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0xFF20394A),
                                          Color(0xFF0C202C),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: AppTheme.teal.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1.4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.teal.withValues(
                                            alpha: 0.22,
                                          ),
                                          blurRadius: 42,
                                          spreadRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.verified_user_rounded,
                                        color: AppTheme.mintBright,
                                        size: 58,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17394A),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.mintBright.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Text(
                              'PRE-PUBLICATION GOVERNANCE',
                              style: AppTheme.monoLabel(
                                color: AppTheme.mintBright,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'BrandGuard',
                                style: AppTheme.headlineLarge.copyWith(
                                  color: Colors.white,
                                  fontSize: 34,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.mintBright,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your brand. Always protected.',
                            style: AppTheme.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) => Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _progress.value,
                            minHeight: 5,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.teal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.settings_ethernet_rounded,
                              size: 13,
                              color: AppTheme.mintBright,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _step,
                              style: AppTheme.monoLabel(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.teal,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Evidence-backed reviews',
                          style: AppTheme.monoLabel(
                            color: Colors.white.withValues(alpha: 0.85),
                          ).copyWith(fontSize: 9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '· v2.4',
                          style: AppTheme.monoLabel(color: AppTheme.mintBright)
                              .copyWith(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No finding without evidence. No approval without a version.',
                    textAlign: TextAlign.center,
                    style: AppTheme.monoLabel(
                      color: Colors.white.withValues(alpha: 0.45),
                    ).copyWith(fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, {Color dot = AppTheme.teal, bool onDark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.monoLabel(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

/// Subtle governance grid.
class GridPainter extends CustomPainter {
  const GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    const step = 44.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rotating verification ring.
class OrbitPainter extends CustomPainter {
  const OrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppTheme.teal.withValues(alpha: 0.28);
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      radius - 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.mintBright.withValues(alpha: 0.14),
    );
    final node = Paint()..color = AppTheme.mintBright;
    canvas.drawCircle(Offset(center.dx, center.dy - radius), 3.4, node);
    canvas.drawCircle(
      Offset(center.dx + radius * 0.86, center.dy + radius * 0.5),
      2.4,
      Paint()..color = AppTheme.teal,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
