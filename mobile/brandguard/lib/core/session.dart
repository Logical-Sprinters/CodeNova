// Simple session management for the BrandGuard prototype
// Stores the signed‑in user and provides helper getters.

import 'package:flutter/material.dart';

class User {
  final String userId;
  final String name;
  final String role;

  User({required this.userId, required this.name, required this.role});

  factory User.fromJson(Map<String, dynamic> json) => User(
        userId: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
      );
}

class Session extends ChangeNotifier {
  static final Session _instance = Session._internal();
  factory Session() => _instance;
  Session._internal();

  User? _currentUser;

  User? get currentUser => _currentUser;
  String? get userId => _currentUser?.userId;
  String? get role => _currentUser?.role;

  void signIn(User user) {
    _currentUser = user;
    notifyListeners();
  }

  void signOut() {
    _currentUser = null;
    notifyListeners();
  }
}

// Global singleton for easy access throughout the app
final session = Session();
