import 'package:flutter/foundation.dart';

class User {
  final String userId;
  final String name;
  final String role;
  final String? email;
  const User({
    required this.userId,
    required this.name,
    required this.role,
    this.email,
  });
  factory User.fromJson(Map<String, dynamic> json) => User(
    userId: (json['user_id'] ?? json['id']) as String,
    name: json['name'] as String? ?? 'User',
    role: json['role'] as String? ?? 'creator',
    email: json['email'] as String?,
  );
  bool get isReviewer => role == 'reviewer' || role == 'admin';
}

/// Tokens remain in memory, not plain SharedPreferences. Remember = email only.
class Session extends ChangeNotifier {
  static final Session _instance = Session._internal();
  factory Session() => _instance;
  Session._internal();
  User? _user;
  String? _accessToken;
  String? _refreshToken;
  User? get currentUser => _user;
  String? get userId => _user?.userId;
  String? get role => _user?.role;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  void signIn(User user, {String? accessToken, String? refreshToken}) {
    _user = user;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    notifyListeners();
  }

  void updateUser(User user) {
    _user = user;
    notifyListeners();
  }

  void signOut() {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    notifyListeners();
  }
}

final session = Session();
