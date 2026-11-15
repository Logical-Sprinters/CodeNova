import 'package:flutter/material.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

/// Sign-in for a prototype: pick who you are.
///
/// There is no password because there is no authentication here, and pretending
/// otherwise would be the one thing this project promises never to do. What is
/// real: the API reads the chosen role from the database on every request, so
/// choosing "creator" cannot make the server let you approve.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late Future<List<User>> _users;

  @override
  void initState() {
    super.initState();
    _users = _load();
  }

  Future<List<User>> _load() async {
    final dynamic data = await Api.get('/users');
    return (data as List<dynamic>)
        .map((dynamic e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.fact_check_outlined, color: Bg.secondary, size: 40),
                  const SizedBox(height: 20),
                  const Text(
                    'BrandGuard',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Bg.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Checks copy against approved, versioned rules — and binds every '
                    'approval to the exact version it approved.',
                    style: TextStyle(fontSize: 15, color: Bg.unsupported, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'SIGN IN AS',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Bg.unsupported,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: AsyncBody<List<User>>(
                      future: _users,
                      isEmpty: (List<User> d) => d.isEmpty,
                      emptyMessage: 'No users yet. Run:  make db',
                      onRetry: () => setState(() => _users = _load()),
                      builder: (BuildContext context, List<User> users) {
                        return ListView.separated(
                          itemCount: users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int i) {
                            final User user = users[i];
                            return Material(
                              color: Bg.card,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  session.signIn(user);
                                   Api.userId = user.id;
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const Shell(),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Bg.line),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      CircleAvatar(
                                        backgroundColor: Bg.primary.withAlpha(20),
                                        child: Text(
                                          user.name.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(
                                            color: Bg.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              user.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              user.role,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Bg.unsupported,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: Bg.unsupported),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Prototype: identity is a header, not a login. Authorisation is '
                    'enforced by the API and independently by the database.',
                    style: TextStyle(fontSize: 11, color: Bg.unsupported, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
