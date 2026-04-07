import '../../api/api_client.dart';

class CostControlService {
  final ApiClient api;

  CostControlService(this.api);

  Future<List<Map<String, dynamic>>> fetchOption1Details({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final data = await api.getJson(
      '/cost-control/option1-details',
      query: _query(
        from: from,
        to: to,
        employeeId: employeeId,
        projectId: projectId,
        taskId: taskId,
      ),
    );
    return _asList(data);
  }

  Future<List<Map<String, dynamic>>> fetchOption2Details({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final data = await api.getJson(
      '/cost-control/option2-details',
      query: _query(
        from: from,
        to: to,
        employeeId: employeeId,
        projectId: projectId,
        taskId: taskId,
      ),
    );
    return _asList(data);
  }

  Future<List<Map<String, dynamic>>> fetchOption1TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final data = await api.getJson(
      '/cost-control/option1-task-summary',
      query: _query(
        from: from,
        to: to,
        employeeId: employeeId,
        projectId: projectId,
        taskId: taskId,
      ),
    );
    return _asList(data);
  }

  Future<List<Map<String, dynamic>>> fetchOption2TaskSummary({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) async {
    final data = await api.getJson(
      '/cost-control/option2-task-summary',
      query: _query(
        from: from,
        to: to,
        employeeId: employeeId,
        projectId: projectId,
        taskId: taskId,
      ),
    );
    return _asList(data);
  }

  Map<String, String> _query({
    required String from,
    required String to,
    String? employeeId,
    String? projectId,
    String? taskId,
  }) {
    final q = <String, String>{
      'from': from.trim(),
      'to': to.trim(),
    };

    if (employeeId != null && employeeId.trim().isNotEmpty) {
      q['employee_id'] = employeeId.trim();
    }
    if (projectId != null && projectId.trim().isNotEmpty) {
      q['project_id'] = projectId.trim();
    }
    if (taskId != null && taskId.trim().isNotEmpty) {
      q['task_id'] = taskId.trim();
    }

    return q;
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (data is Map && data['rows'] is List) {
      return (data['rows'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }
}