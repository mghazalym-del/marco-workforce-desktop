import 'dart:convert';
import 'package:http/http.dart' as http;

class WorkforceStructureService {
  static const String _baseUrl =
      'https://fireless-nontabulated-margarett.ngrok-free.dev/api/v1';
  static const String _token = 'DEV-TOKEN-E9001';

  Future<Map<String, dynamic>> fetchProjectTree({
    required String projectId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/workforce-structure/${Uri.encodeComponent(projectId)}/tree',
    );

    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load workforce structure: ${response.body}');
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    if (jsonData['success'] != true) {
      throw Exception('Workforce structure API returned failure.');
    }

    return Map<String, dynamic>.from(jsonData['data'] as Map);
  }
Future<void> reassign({
  required String projectId,
  required String employeeId,
  required String newManagerId,
  required String updatedBy,
}) async {
  final uri = Uri.parse('$_baseUrl/workforce-structure/reassign');

  final response = await http.post(
    uri,
    headers: {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'project_id': projectId,
      'employee_id': employeeId,
      'new_reports_to_employee_id': newManagerId,
      'updated_by': updatedBy,
    }),
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Reassign failed: ${response.body}');
  }

  final jsonData = jsonDecode(response.body);
  if (jsonData['success'] != true) {
    throw Exception('Reassign API failed');
  }
}

Future<List<Map<String, dynamic>>> fetchProjectFlat({
  required String projectId,
}) async {
  final res = await fetchProjectTree(projectId: projectId);

  final List<Map<String, dynamic>> flat = [];

  void walk(List nodes) {
    for (final n in nodes) {
      final node = Map<String, dynamic>.from(n);
      flat.add(node);
      if (node['children'] != null) {
        walk(node['children']);
      }
    }
  }

  walk(res['tree'] ?? []);
  return flat;
}
}