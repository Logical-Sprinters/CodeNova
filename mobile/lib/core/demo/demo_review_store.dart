import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Display-only local sample data for the dashboard and demo analytics.
/// The real review queue is loaded independently from FastAPI.
class DemoReviewStore {
  static const String _storageKey = 'brandguard_reviews_v1';

  static final List<Map<String, dynamic>> reviews = [
    {
      'id': 'BG-2026-001',
      'title': 'Q3 Global Cloud Launch',
      'creator': 'Alex Morgan',
      'channel': 'LinkedIn',
      'date': '14 Nov 2026',
      'status': 'Pending',
      'findings': 4,
      'version': 'v1.0',
      'risk': 'High',
      'description': 'Enterprise cloud campaign containing pricing, uptime and customer adoption claims.',
    },
    {
      'id': 'BG-2026-002',
      'title': 'ApexShield Product Announcement',
      'creator': 'Sarah Chen',
      'channel': 'Instagram',
      'date': '13 Nov 2026',
      'status': 'Pending',
      'findings': 2,
      'version': 'v2.0',
      'risk': 'Medium',
      'description': 'Product announcement with claims requiring authorised source verification.',
    },
    {
      'id': 'BG-2026-003',
      'title': 'Enterprise Security Newsletter',
      'creator': 'Jordan Lee',
      'channel': 'Email',
      'date': '12 Nov 2026',
      'status': 'Changes Requested',
      'findings': 3,
      'version': 'v1.2',
      'risk': 'Medium',
      'description': 'Newsletter requiring revised compliance language and supporting evidence.',
    },
    {
      'id': 'BG-2026-004',
      'title': 'Cloud Migration Campaign',
      'creator': 'Taylor Smith',
      'channel': 'Website',
      'date': '11 Nov 2026',
      'status': 'Approved',
      'findings': 1,
      'version': 'v1.0',
      'risk': 'Low',
      'description':
          'Reviewed campaign with documented evidence and authorised approval.',
    },
  ];

  static bool _isInitialized = false;
  static Future<void>? _initializationFuture;

  /// Loads persisted reviews once. Existing demo records are retained on first launch.
  static Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    return _initializationFuture ??= _loadFromStorage();
  }

  static Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString(_storageKey);

      if (savedData != null) {
        final decoded = jsonDecode(savedData);
        if (decoded is List) {
          reviews
            ..clear()
            ..addAll(
              decoded.whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ),
            );
        }
      } else {
        await prefs.setString(_storageKey, jsonEncode(reviews));
      }

      _isInitialized = true;
    } catch (error) {
      // Keep the in-memory demo data usable if local storage cannot be read.
      _isInitialized = true;
    }
  }
}
