import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  final String? token;

  ApiClient({required this.baseUrl, this.token});

  // -----------------------
  // URL builder (safe join)
  // -----------------------
  Uri _buildUri(String path, {Map<String, String>? query}) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final cleanPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse(cleanBase + cleanPath).replace(
      queryParameters: (query != null && query.isNotEmpty) ? query : null,
    );
  }

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final t = token;
    if (t != null && t.isNotEmpty) {
      headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  // =====================
  // GET JSON (Map or List)
  // =====================
  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    final uri = _buildUri(path, query: query);
    final res = await http.get(uri, headers: _headers());
    return _handleResponse(res);
  }

  // =====================
  // ✅ Needed by Workers page
  // GET JSON List
  // =====================
  Future<List<dynamic>> getJsonList(String path, {Map<String, String>? query}) async {
    final data = await getJson(path, query: query);
    if (data is List) return data;
    if (data is Map && data['data'] is List) return List<dynamic>.from(data['data']);
    if (data is Map && data['data'] is Map) {
      // common shape: { success:true, data:{ workers:[...] } }
      final inner = data['data'];
      if (inner is Map) {
        for (final v in inner.values) {
          if (v is List) return List<dynamic>.from(v);
        }
      }
    }
    throw ApiException(statusCode: 500, body: 'Expected List JSON but got: ${data.runtimeType}');
  }

  // =====================
  // POST JSON
  // Supports BOTH:
  // - postJson(path, body: {...})   ✅ your code uses this
  // - postJson(path, {...})        (compat)
  // =====================
  Future<dynamic> postJson(String path, {Map<String, dynamic>? body, Map<String, dynamic>? data}) async {
    // allow either "body" (your codebase) or "data" (compat)
    final payload = body ?? data ?? <String, dynamic>{};

    final uri = _buildUri(path);
    final res = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(payload),
    );
    return _handleResponse(res);
  }

  // =====================
  // PATCH JSON
  // Supports BOTH:
  // - patchJson(path, body: {...}) ✅ your code uses this
  // - patchJson(path, {...})       (compat)
  // =====================
  Future<dynamic> patchJson(String path, {Map<String, dynamic>? body, Map<String, dynamic>? data}) async {
    final payload = body ?? data ?? <String, dynamic>{};

    final uri = _buildUri(path);
    final res = await http.patch(
      uri,
      headers: _headers(),
      body: jsonEncode(payload),
    );
    return _handleResponse(res);
  }

  // -----------------------
  // Response handler
  // -----------------------
  dynamic _handleResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }

    // JSON-safe exception even if ngrok returns HTML
    throw ApiException(statusCode: res.statusCode, body: res.body);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException({required this.statusCode, required this.body});

  @override
  String toString() => 'ApiException($statusCode): $body';
}
