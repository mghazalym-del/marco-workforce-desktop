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
      for (final entry in m.entries) {
        if (entry.value is List) {
          return (entry.value as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
      }
    }
    return <Map<String, dynamic>>[];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      // ✅ Correct base: /api/v1/monitor (NOT /monitor)
      // ✅ Backend requires work_date
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': widget.workDate},
      );

      setState(() {
        workers = _extractList(json, dataKey: 'workers');
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
        final openTask = (w['open_task'] ?? '-').toString();

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
