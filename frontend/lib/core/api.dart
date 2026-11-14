import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The one place that knows how to talk to the API.
///
/// The base URL resolves itself so the classic emulator trap cannot happen: an
/// Android emulator cannot reach the host's "localhost", it needs 10.0.2.2.
/// Override it for a phone on the same Wi-Fi:
///   flutter run --dart-define=API_BASE=http://192.168.1.20:8000
class Api {
  Api._();

  /// Who is making the request. Set by the sign-in screen; the server re-reads
  /// the role from the database, so this cannot be used to grant a permission.
  static String? userId;

  static String get base {
    const String fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

  static Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (userId != null) 'X-User-Id': userId!,
      };

  static Future<dynamic> get(String path) async {
    final http.Response response = await http
        .get(Uri.parse('$base$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final http.Response response = await http
        .post(
          Uri.parse('$base$path'),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  static dynamic _decode(http.Response response) {
    dynamic parsed;
    try {
      parsed = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(response.statusCode, <String, dynamic>{
        'detail': 'the server returned something that is not JSON '
            '(HTTP ${response.statusCode}).'
      });
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, parsed);
    }
    return parsed;
  }
}

/// A refusal from the API, carrying the server's own words. A demo that says
/// "a reviewer cannot approve while a confirmed match stands" is worth ten that
/// say "something went wrong".
class ApiException implements Exception {
  ApiException(this.status, this.body);

  final int status;
  final dynamic body;

  String get message {
    final dynamic detail = body is Map ? (body as Map)['detail'] : null;
    if (detail is String) return detail;
    if (detail is Map && detail['error'] != null) return detail['error'].toString();
    if (body is List) return 'request refused ($status)';
    return 'request failed ($status)';
  }

  @override
  String toString() => message;
}
