
import 'dart:convert';
import 'package:http/http.dart' as http;

class BrandGuardApiService {
  // For Flutter Web running in Chrome.
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> checkBrand({
    required String brandName,
    required String content,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/brand/check'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'brand_name': brandName,
            'content': content,
            'content_type': 'text',
          }),
        )
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> getReviews({
    String? status,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/reviews').replace(
      queryParameters: status == null ? null : {'status': status},
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 15),
    );

    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> decideReview({
    required String checkId,
    required String decision,
    String reviewer = 'Admin',
    String note = '',
  }) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/v1/reviews/$checkId/decision'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'decision': decision,
            'reviewer': reviewer,
            'note': note,
          }),
        )
        .timeout(const Duration(seconds: 15));

    return _handleResponse(response);
  }

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

  static Map<String, dynamic> _handleResponse(
    http.Response response,
  ) {
    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 &&
        response.statusCode < 300) {
      return data;
    }

    final error = data['detail'] ?? 'Something went wrong';

    throw Exception(error.toString());
  }
}
