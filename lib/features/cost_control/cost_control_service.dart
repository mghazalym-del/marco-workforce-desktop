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
    final uri = Uri.parse(
      '$_baseUrl/cost-control/option1-details'
      '?from=$from&to=$to'
      '${_q('employee_id', employeeId)}'
      '${_q('project_id', projectId)}'
      '${_q('task_id', taskId)}',
    );

    final response = await http.get(
      uri,
      headers: _headers,
    );

    return _parseListResponse(response, 'Option 1 details');
  }

  Future<List<Map<String, dynamic>>> fetchOption2Details({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/cost-control/option2-details'
      '?from=$from&to=$to'
      '${_q('employee_id', employeeId)}'
      '${_q('project_id', projectId)}'
      '${_q('task_id', taskId)}',
    );

    final response = await http.get(
      uri,
      headers: _headers,
    );

    return _parseListResponse(response, 'Option 2 details');
  }

  Future<List<Map<String, dynamic>>> fetchOption1TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/cost-control/option1-task-summary'
      '?from=$from&to=$to'
      '${_q('employee_id', employeeId)}'
      '${_q('project_id', projectId)}'
      '${_q('task_id', taskId)}',
    );

    final response = await http.get(
      uri,
      headers: _headers,
    );

    return _parseListResponse(response, 'Option 1 task summary');
  }

  Future<List<Map<String, dynamic>>> fetchOption2TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/cost-control/option2-task-summary'
      '?from=$from&to=$to'
      '${_q('employee_id', employeeId)}'
      '${_q('project_id', projectId)}'
      '${_q('task_id', taskId)}',
    );

    final response = await http.get(
      uri,
      headers: _headers,
    );

    return _parseListResponse(response, 'Option 2 task summary');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  String _q(String key, String? value) {
    if (value == null || value.trim().isEmpty) return '';
    return '&$key=${Uri.encodeQueryComponent(value.trim())}';
  }

  List<Map<String, dynamic>> _parseListResponse(
    http.Response response,
    String label,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load $label: ${response.body}');
    }

    final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
    final success = jsonData['success'] == true;
    if (!success) {
      throw Exception('$label API returned failure.');
    }

    final data = jsonData['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return [];
  }
}