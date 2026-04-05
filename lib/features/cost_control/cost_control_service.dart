import 'dart:convert';
import 'package:http/http.dart' as http;

class CostControlService {
  static const String _baseUrl =
      'https://fireless-nontabulated-margarett.ngrok-free.dev/api/v1';
  static const String _token = 'DEV-TOKEN-E9001';

  Future<List<Map<String, dynamic>>> fetchOption1Details({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = _buildUri(
      '/cost-control/option1-details',
      from: from,
      to: to,
      employeeId: employeeId,
      projectId: projectId,
      taskId: taskId,
    );

    final response = await http.get(uri, headers: _headers);
    return _parseListResponse(response, 'Option 1 details');
  }

  Future<List<Map<String, dynamic>>> fetchOption2Details({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = _buildUri(
      '/cost-control/option2-details',
      from: from,
      to: to,
      employeeId: employeeId,
      projectId: projectId,
      taskId: taskId,
    );

    final response = await http.get(uri, headers: _headers);
    return _parseListResponse(response, 'Option 2 details');
  }

  Future<List<Map<String, dynamic>>> fetchOption1TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = _buildUri(
      '/cost-control/option1-task-summary',
      from: from,
      to: to,
      employeeId: employeeId,
      projectId: projectId,
      taskId: taskId,
    );

    final response = await http.get(uri, headers: _headers);
    return _parseListResponse(response, 'Option 1 task summary');
  }

  Future<List<Map<String, dynamic>>> fetchOption2TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = _buildUri(
      '/cost-control/option2-task-summary',
      from: from,
      to: to,
      employeeId: employeeId,
      projectId: projectId,
      taskId: taskId,
    );

    final response = await http.get(uri, headers: _headers);
    return _parseListResponse(response, 'Option 2 task summary');
  }

  Uri _buildUri(
    String path, {
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) {
    final qp = <String, String>{
      'from': from,
      'to': to,
    };

    if (employeeId != null && employeeId.trim().isNotEmpty) {
      qp['employee_id'] = employeeId.trim();
    }
    if (projectId != null && projectId.trim().isNotEmpty) {
      qp['project_id'] = projectId.trim();
    }
    if (taskId != null && taskId.trim().isNotEmpty) {
      qp['task_id'] = taskId.trim();
    }

    return Uri.parse('$_baseUrl$path').replace(queryParameters: qp);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': '1',
      };

  List<Map<String, dynamic>> _parseListResponse(
    http.Response response,
    String label,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load $label: ${response.body}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      if (decoded['success'] == false) {
        throw Exception('$label API returned failure: ${decoded['error'] ?? decoded}');
      }

      final data = decoded['data'];
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (data is Map<String, dynamic> && data['rows'] is List) {
        return (data['rows'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }

    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return [];
  }
}