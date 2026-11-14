import 'dart:math' as math;


import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;

import 'screens/auth/sign_in_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrandGuardApp());
}

class BrandGuardApp extends StatelessWidget {
  const BrandGuardApp({super.key});

  static const navy = Color(0xFF142C3B);
  static const teal = Color(0xFF22A895);
  static const mint = Color(0xFF81F7E1);
  static const background = Color(0xFFF7F8F5);

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
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        textTheme: GoogleFonts.manropeTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: navy,
          secondary: teal,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  late final AnimationController _introController;
  late final AnimationController _orbitController;
  late final Animation<double> _introFade;
  late final Animation<Offset> _introSlide;

  @override
  void initState() {
    super.initState();

    // Show the branded splash screen briefly, then open Sign In.
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();
    _introFade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
    );
    _introSlide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    ));

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _introController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: BrandGuardApp.navy),
            ),
          ),
          Positioned(
            top: -110,
            left: -110,
            child: _glow(
              280,
              BrandGuardApp.teal.withValues(alpha: 0.23),
            ),
          ),
          Positioned(
            top: 260,
            right: -130,
            child: _glow(
              260,
              BrandGuardApp.mint.withValues(alpha: 0.13),
            ),
          ),
          Positioned(
            bottom: -100,
            left: 80,
            child: _glow(
              250,
              Colors.blueGrey.withValues(alpha: 0.15),
            ),
          ),
          const Positioned.fill(
            child: CustomPaint(painter: GridPainter()),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 22,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _securityBadge(),
                      Row(
                        children: [
                          const Icon(
                            Icons.lock,
                            size: 15,
                            color: BrandGuardApp.mint,
                          ),
                          const SizedBox(width: 6),
                          Text('256-BIT', style: _labelStyle()),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale =
                          1 + (_pulseController.value * 0.035);
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: Column(
                      children: [
                        SizedBox(
                          width: 176,
                          height: 176,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _orbitController,
                                builder: (context, child) => Transform.rotate(
                                  angle: _orbitController.value * 2 * math.pi,
                                  child: child,
                                ),
                                child: CustomPaint(
                                  size: const Size(176, 176),
                                  painter: OrbitPainter(),
                                ),
                              ),
                              Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BrandGuardApp.teal.withValues(
                              alpha: 0.12,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: BrandGuardApp.mint.withValues(
                                  alpha: 0.15,
                                ),
                                blurRadius: 55,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(23),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF203E50),
                                    Color(0xFF0C202C),
                                  ],
                                ),
                                border: Border.all(
                                  color: BrandGuardApp.teal,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: CustomPaint(
                                  size: Size(60, 70),
                                  painter: ShieldPainter(),
                                ),
                              ),
                            ),
                          ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF001725),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'AUDITED',
                            style: GoogleFonts.manrope(
                              color: BrandGuardApp.mint,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 35),
                  FadeTransition(
                    opacity: _introFade,
                    child: SlideTransition(
                      position: _introSlide,
                      child: Column(
                        children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'BrandGuard',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontSize: 29,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: BrandGuardApp.mint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Your brand. Always protected.',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFFD3E5F1),
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return Column(
                        children: [
                          Container(
                            width: 195,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor:
                                    0.67 * _progressController.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: const LinearGradient(
                                      colors: [
                                        BrandGuardApp.mint,
                                        BrandGuardApp.teal,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.sync,
                                size: 14,
                                color: BrandGuardApp.mint,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'VERIFYING GOVERNANCE ENGINE',
                                style: _labelStyle(),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF001725).withValues(
                        alpha: 0.65,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: BrandGuardApp.mint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            'Enterprise Pre-Publication Governance',
                            style: GoogleFonts.manrope(
                              color: const Color(0xFFE2F3FF),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'v2.4',
                          style: GoogleFonts.manrope(
                            color: BrandGuardApp.mint,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    'No finding without evidence. No approval without a version.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF7C94A6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  Widget _securityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: BrandGuardApp.mint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('VAULT SECURE', style: _labelStyle()),
        ],
      ),
    );
  }

  TextStyle _labelStyle() {
    return GoogleFonts.manrope(
      color: const Color(0xFFD3E5F1),
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    );
  }
}

class OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;
    final ringPaint = Paint()
      ..color = BrandGuardApp.mint.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, ringPaint);

    final glowPaint = Paint()
      ..color = BrandGuardApp.mint
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(center.dx, center.dy - radius), 4, glowPaint);
    final dotPaint = Paint()..color = BrandGuardApp.teal;
    canvas.drawCircle(Offset(center.dx, center.dy + radius), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant OrbitPainter oldDelegate) => false;
}

class GridPainter extends CustomPainter {
  const GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BrandGuardApp.mint.withValues(alpha: 0.045)
      ..strokeWidth = 0.5;

    const gap = 32.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => false;
}

class ShieldPainter extends CustomPainter {
  const ShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shield = Path()
      ..moveTo(size.width / 2, 2)
      ..lineTo(size.width * 0.12, size.height * 0.18)
      ..lineTo(size.width * 0.12, size.height * 0.45)
      ..cubicTo(
        size.width * 0.12,
        size.height * 0.72,
        size.width * 0.30,
        size.height * 0.91,
        size.width / 2,
        size.height - 2,
      )
      ..cubicTo(
        size.width * 0.70,
        size.height * 0.91,
        size.width * 0.88,
        size.height * 0.72,
        size.width * 0.88,
        size.height * 0.45,
      )
      ..lineTo(size.width * 0.88, size.height * 0.18)
      ..close();

    final fill = Paint()
      ..color = const Color(0xFF001725)
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = BrandGuardApp.mint
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(shield, fill);
    canvas.drawPath(shield, outline);

    final check = Path()
      ..moveTo(size.width * 0.29, size.height * 0.49)
      ..lineTo(size.width * 0.44, size.height * 0.64)
      ..lineTo(size.width * 0.72, size.height * 0.35);

    final checkPaint = Paint()
      ..color = BrandGuardApp.mint
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(check, checkPaint);

    final dotPaint = Paint()..color = BrandGuardApp.mint;

    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.20),
      2,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant ShieldPainter oldDelegate) => false;
}
