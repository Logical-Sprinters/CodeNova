import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/session.dart';
import 'api_config.dart';

/// A short safe message for the UI, not a socket/URL/stack-trace dump.
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BrandGuardApiService {
  static http.Client _client = http.Client();
  static Future<void>? _refreshing;
  @visibleForTesting
  static set clientForTesting(http.Client value) {
    _client.close();
    _client = value;
    _refreshing = null;
  }

  static String get baseUrl => ApiConfig.resolveBaseUrl(
    configuredBase: const String.fromEnvironment('API_BASE'),
    isWeb: kIsWeb,
    webOrigin: kIsWeb ? Uri.base.origin : null,
  );

  static Future<http.Response> _send(
    http.BaseRequest request, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      // Bound both connection setup AND reading the response body.
      return await (() async {
        final response = await _client.send(request);
        return http.Response.fromStream(response);
      })().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        'Connection timed out. Check your internet, wait a moment and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the BrandGuard server. Check your internet connection and try again.',
      );
    }
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (session.accessToken case final String token)
      'Authorization': 'Bearer $token',
  };

  static Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'The server returned an unexpected non-JSON response (HTTP ${response.statusCode}). Please try again.',
      );
    }
    if (decoded is! Map) {
      throw const ApiException(
        'The server returned an invalid response. Please try again.',
      );
    }
    final data = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final detail =
        data['detail'] ??
        data['message'] ??
        'Request failed (HTTP ${response.statusCode})';
    final message = detail is List
        ? detail.map((e) => e is Map ? e['msg'] : e).join('; ')
        : detail.toString();
    throw ApiException(message);
  }

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    if (authenticated && session.accessToken == null) {
      throw const ApiException('Please sign in first.');
    }
    final requestToken = session.accessToken;
    final requestUser = session.userId;
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers.addAll(
      authenticated ? _headers : {'Content-Type': 'application/json'},
    );
    if (body != null) req.body = jsonEncode(body);
    final response = await _send(req);
    if (response.statusCode == 401 &&
        authenticated &&
        retry &&
        session.refreshToken != null) {
      if (session.userId != requestUser) {
        throw const ApiException(
          'Session changed. Retry from your current account.',
        );
      }
      if (session.accessToken == requestToken) {
        final refreshing = _refreshing ??= _refreshSession();
        try {
          await refreshing;
        } finally {
          if (identical(_refreshing, refreshing)) _refreshing = null;
        }
      }
      return request(
        method,
        path,
        body: body,
        authenticated: true,
        retry: false,
      );
    }
    return _decode(response);
  }

  static void _acceptSession(Map<String, dynamic> data) {
    if (data['access_token'] is! String || data['user'] is! Map) {
      throw const ApiException(
        'The server did not create a session. Please try signing in again.',
      );
    }
    session.signIn(
      User.fromJson(Map<String, dynamic>.from(data['user'])),
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String?,
    );
  }

  static Future<void> login(String email, String password) async {
    _acceptSession(
      await request(
        'POST',
        '/api/v1/auth/login',
        authenticated: false,
        body: {'email': email.trim(), 'password': password},
      ),
    );
  }

  static Future<Map<String, dynamic>> signup(
    String name,
    String email,
    String password,
  ) async {
    final data = await request(
      'POST',
      '/api/v1/auth/signup',
      authenticated: false,
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
    if (data['requires_confirmation'] == true) return data;
    _acceptSession(data);
    return data;
  }

  static Future<void> _refreshSession() async {
    final refresh = session.refreshToken;
    try {
      final data = await request(
        'POST',
        '/api/v1/auth/refresh',
        authenticated: false,
        body: {'refresh_token': refresh},
      );
      if (session.refreshToken != refresh) {
        throw const ApiException('Session changed during refresh.');
      }
      _acceptSession(data);
    } catch (_) {
      if (session.refreshToken == refresh) session.signOut();
      rethrow;
    }
  }

  static Future<void> signOut() async {
    final token = session.accessToken;
    session.signOut();
    if (token == null) return;
    try {
      final req = http.Request(
        'POST',
        Uri.parse('$baseUrl/api/v1/auth/logout'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      await _send(req, timeout: const Duration(seconds: 4));
    } catch (_) {
      /* Local logout succeeds even offline; remote revocation then cannot be guaranteed. */
    }
  }

  static Future<void> recover(String email) async {
    await request(
      'POST',
      '/api/v1/auth/recover',
      authenticated: false,
      body: {'email': email.trim()},
    );
  }

  static Future<Map<String, dynamic>> getJson(String path) =>
      request('GET', path);
  static Future<Map<String, dynamic>> checkBrand({
    required String brandName,
    required String content,
  }) => request(
    'POST',
    '/api/v1/brand/check',
    body: {'brand_name': brandName, 'content': content, 'content_type': 'text'},
  );
  static Future<Map<String, dynamic>> getReviews({String? status}) => getJson(
    '/api/v1/reviews${status == null ? '' : '?status=${Uri.encodeQueryComponent(status)}'}',
  );
  static Future<Map<String, dynamic>> getReceipt({required String receiptId}) =>
      getJson('/api/v1/receipts/${Uri.encodeComponent(receiptId)}');
  static Future<Map<String, dynamic>> submitEditedContent({
    required String checkId,
    required String content,
    int? expectedVersion,
  }) => request(
    'POST',
    '/api/v1/brand/$checkId/versions',
    body: {'content': content, 'expected_version': ?expectedVersion},
  );
  static Future<Map<String, dynamic>> decideReview({
    required String checkId,
    required String decision,
    String note = '',
    int? expectedVersion,
  }) => request(
    'PATCH',
    '/api/v1/reviews/$checkId/decision',
    body: {
      'decision': decision,
      'note': note,
      'expected_version': ?expectedVersion,
    },
  );
  static Future<Map<String, dynamic>> verifyApproval({
    required String checkId,
    required String brandName,
    required String content,
  }) => request(
    'POST',
    '/api/v1/approvals/verify',
    body: {'check_id': checkId, 'brand_name': brandName, 'content': content},
  );
  static Future<Map<String, dynamic>> saveDraft(
    Map<String, dynamic> body, {
    String? id,
  }) => request(
    id == null ? 'POST' : 'PUT',
    '/api/v1/drafts${id == null ? '' : '/$id'}',
    body: body,
  );
  static Future<Map<String, dynamic>> uploadDocument(
    String name,
    Uint8List bytes, {
    bool asFact = false,
    String brandName = 'Acme',
  }) async {
    if (session.accessToken == null) {
      throw const ApiException('Please sign in first.');
    }
    final req = http.MultipartRequest(
      'POST',
      Uri.parse(
        '$baseUrl/api/v1/files?as_fact=$asFact&brand_name=${Uri.encodeQueryComponent(brandName)}',
      ),
    );
    req.headers['Authorization'] = 'Bearer ${session.accessToken}';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    return _decode(await _send(req));
  }
}
