import 'session.dart';

/// Public local-demo autofill values only. Authentication is always performed
/// by the backend; this class never verifies credentials or creates a session.
class DemoAccount {
  const DemoAccount({
    required this.email,
    required this.userId,
    required this.name,
    required this.role,
  });

  final String email;
  final String userId;
  final String name;
  final String role;

  String get roleLabel => role == 'reviewer' ? 'Reviewer' : 'Creator';

  User get user => User(userId: userId, name: name, role: role, email: email);
}

class DemoAuth {
  DemoAuth._();

  // DEMO ONLY. Never reuse this public password for real users/services.
  static const String password = 'Demo@12345';
  static const String rememberedEmailKey = 'bg_demo_last_email';
  static const String rememberEmailKey = 'bg_demo_remember_email';

  static const creator = DemoAccount(
    email: 'creator@brandguard.demo',
    userId: 'u1',
    name: 'Alice',
    role: 'creator',
  );

  static const reviewer = DemoAccount(
    email: 'reviewer@brandguard.demo',
    userId: 'u2',
    name: 'Bob',
    role: 'reviewer',
  );

  static const List<DemoAccount> accounts = [creator, reviewer];

  static DemoAccount? findAccount(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    for (final account in accounts) {
      if (account.email == normalizedEmail) return account;
    }
    return null;
  }
}
