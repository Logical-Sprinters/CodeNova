import 'package:flutter/material.dart';

import 'app/theme.dart';
import 'features/sign_in/sign_in_screen.dart';

void main() => runApp(const BrandGuardApp());

class BrandGuardApp extends StatelessWidget {
  const BrandGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrandGuard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const SignInScreen(),
    );
  }
}
