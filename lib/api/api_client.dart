import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  final String? token;

  static const String _apiPrefix = '/api/v1';

  ApiClient({required this.baseUrl, this.token});

  // -----------------------
  // URL builder (forces /api/v1)
  // -----------------------
  Uri _buildUri(String path, {Map<String, String>? query}) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final normalizedPath = path.startsWith('/')
        ? path
        : '/$path';

    final fullPath = normalizedPath.startsWith(_apiPrefix)
        ? normalizedPath
        : '$_apiPrefix$normalizedPath';

    return Uri.parse(cleanBase + fullPath).replace(
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
  // GET → returns data only
  // =====================
  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    final uri = _buildUri(path, query: query);
    print("GET => $uri");
    final res = await http.get(uri, headers: _headers());
    final decoded = _handleResponse(res);

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  // =====================
  // GET → List only (explicit)
  // =====================
  Future<List<dynamic>> getJsonList(String path, {Map<String, String>? query}) async {
    final data = await getJson(path, query: query);

    if (data is List) {
      return List<dynamic>.from(data);
    }

    throw ApiException(
      statusCode: 500,
      body: 'Expected List JSON but got: ${data.runtimeType}',
    );
  }

  // =====================
  // POST JSON
  // =====================
  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data ?? <String, dynamic>{};
    final uri = _buildUri(path);
    final res = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(payload),
    );
    return _unwrap(_handleResponse(res));
  }

  // =====================
  // PATCH JSON
  // =====================
  Future<dynamic> patchJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data ?? <String, dynamic>{};
    final uri = _buildUri(path);
    final res = await http.patch(
      uri,
      headers: _headers(),
      body: jsonEncode(payload),
    );
    return _unwrap(_handleResponse(res));
  }

  // -----------------------
  // Helpers
  // -----------------------
  dynamic _unwrap(dynamic decoded) {
    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  dynamic _handleResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
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
