import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class SupervisorDayWorkersPage extends StatefulWidget {
  final ApiClient api;
  final String supervisorId;
  final String workDate;

  const SupervisorDayWorkersPage({
    super.key,
    required this.api,
    required this.supervisorId,
    required this.workDate,
  });

  @override
  State<SupervisorDayWorkersPage> createState() => _SupervisorDayWorkersPageState();
}

class _SupervisorDayWorkersPageState extends State<SupervisorDayWorkersPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> workers = [];

  List<Map<String, dynamic>> _extractList(dynamic json, {String? dataKey}) {
    dynamic v = json;
    if (v is Map<String, dynamic> && v.containsKey('data')) v = v['data'];

    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (v is Map) {
      final m = v.cast<String, dynamic>();
      if (dataKey != null && m[dataKey] is List) {
        return (m[dataKey] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
      // fallback: first list value
      for (final entry in m.entries) {
        if (entry.value is List) {
          return (entry.value as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    }
    return <Map<String, dynamic>>[];
  }

  String _openTaskText(dynamic openTask) {
    if (openTask == null) return '-';
    if (openTask is String) return openTask.isEmpty ? '-' : openTask;
    if (openTask is Map) {
      final m = openTask.cast<String, dynamic>();
      final pid = (m['project_id'] ?? '').toString();
      final tid = (m['task_id'] ?? '').toString();
      final start = (m['start_ts'] ?? '').toString();
      final parts = <String>[];
      if (pid.isNotEmpty) parts.add(pid);
      if (tid.isNotEmpty) parts.add(tid);
      if (start.isNotEmpty) parts.add('since $start');
      return parts.isEmpty ? 'OPEN' : parts.join(' • ');
    }
    return openTask.toString();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _getWorkerSummary(String employeeId) async {
    final json = await widget.api.getJson(
      '/api/v1/assignments/day/summary/$employeeId',
      query: {'work_date': widget.workDate},
    );

    // api_client may return {success,data:{...}} OR already data
    dynamic v = json;
    if (v is Map<String, dynamic> && v.containsKey('data')) v = v['data'];
    if (v is Map) return v.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      workers = [];
    });

    try {
      // 1) workers list from monitor
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': widget.workDate},
      );

      final baseWorkers = _extractList(json, dataKey: 'workers');

      // 2) enrich each worker with assignments summary so UI can show sessions/minutes/open_task
      final enriched = <Map<String, dynamic>>[];
      for (final w in baseWorkers) {
        final id = (w['employee_id'] ?? '').toString();
        if (id.isEmpty) {
          enriched.add(w);
          continue;
        }

        Map<String, dynamic> summary = {};
        try {
          summary = await _getWorkerSummary(id);
        } catch (_) {
          summary = {};
        }

        enriched.add({
          ...w,
          'sessions_count': summary['sessions_count'] ?? summary['sessions'] ?? 0,
          'total_minutes': summary['total_minutes'] ?? summary['minutes'] ?? 0,
          'open_task': summary['open_task'],
        });
      }

      setState(() {
        workers = enriched;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text("Error: $error"));
    if (workers.isEmpty) return const Center(child: Text("No workers found"));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: workers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final w = workers[i];
        final id = (w['employee_id'] ?? '').toString();
        final name = (w['full_name'] ?? '').toString();
        final dayStatus = (w['day_status'] ?? 'N/A').toString();

        final sessions = (w['sessions_count'] ?? 0).toString();
        final minutes = (w['total_minutes'] ?? 0).toString();
        final openTask = _openTaskText(w['open_task']);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("$name ($id)", style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text("Day status: $dayStatus"),
              Text("Sessions: $sessions"),
              Text("Total minutes: $minutes"),
              Text("Open task: $openTask"),
            ],
          ),
        );
      },
    );
  }
}
