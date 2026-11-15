// BrandGuard API service for Flutter Web client
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/session.dart';

class BrandGuardApiService {
  // Base URL for the FastAPI backend (running locally)
  static const String baseUrl = 'http://127.0.0.1:8000';

  // ---------------------------------------------------------------
  // Checks a brand and creates a new check record.
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> checkBrand({
    required String brandName,
    required String content,
  }) async {
    // Include user identification header from session singleton
    final headers = {
      'Content-Type': 'application/json',
      if (session.userId != null) 'X-User-Id': session.userId!,
    };
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/brand/check'),
          headers: headers,
          body: jsonEncode({
            'brand_name': brandName,
            'content': content,
            'content_type': 'text',
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }


  // ---------------------------------------------------------------
  // Retrieve list of reviews (optionally filtered by status).
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> getReviews({String? status}) async {
    final uri = Uri.parse('$baseUrl/api/v1/reviews').replace(
      queryParameters: status == null ? null : {'status': status},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------
  // Retrieve a receipt by its ID.
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> getReceipt({required String receiptId}) async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/v1/receipts/$receiptId'))
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------
  // Submit a new version (edited content) for a check.
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> submitEditedContent({
    required String checkId,
    required String content,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/brand/$checkId/versions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'content': content}),
        )
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------
  // Reviewer decision (approve / reject).
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> decideReview({
    required String checkId,
    required String decision,
    String reviewer = 'Admin',
    String note = '',
  }) async {
    // Include user identification header from session singleton
    final headers = {
      'Content-Type': 'application/json',
      if (session.userId != null) 'X-User-Id': session.userId!,
    };
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/v1/reviews/$checkId/decision'),
          headers: headers,
          body: jsonEncode({
            'decision': decision,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------
  // Verify an approval using the backend endpoint.
  // ---------------------------------------------------------------
  static Future<Map<String, dynamic>> verifyApproval({
    required String checkId,
    required String brandName,
    required String content,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/approvals/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'check_id': checkId,
            'brand_name': brandName,
            'content': content,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  // ---------------------------------------------------------------
  // Internal helper to decode JSON and handle HTTP errors.
  // ---------------------------------------------------------------
  static Map<String, dynamic> _handleResponse(http.Response response) {
    final Map<String, dynamic> data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    final error = data['detail'] ?? 'Something went wrong';
    throw Exception(error.toString());
  }
}
