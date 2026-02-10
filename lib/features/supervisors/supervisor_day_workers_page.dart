import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
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
  State<SupervisorDayWorkersPage> createState() =>
      _SupervisorDayWorkersPageState();
}

class _SupervisorDayWorkersPageState
    extends State<SupervisorDayWorkersPage> {
  bool loading = true;
  List<Map<String, dynamic>> workers = [];
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 🔑 CRITICAL FIX
  /// This is what was missing.
  /// When the top date OR supervisor changes, reload data.
  @override
  void didUpdateWidget(covariant SupervisorDayWorkersPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.workDate != widget.workDate ||
        oldWidget.supervisorId != widget.supervisorId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      workers = [];
    });

    try {
      // 1️⃣ Get workers for supervisor/day
      final res = await widget.api.getJson(
        '/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': widget.workDate},
      );

      final List list = (res is Map && res['workers'] is List)
          ? res['workers']
          : (res is List ? res : []);

      // 2️⃣ Enrich each worker with assignments/day/summary
      final enriched = <Map<String, dynamic>>[];

      for (final w in list) {
        final empId = w['employee_id']?.toString();
        if (empId == null) continue;

        final summary = await widget.api.getJson(
          '/assignments/day/summary/$empId',
          query: {'work_date': widget.workDate},
        );

        enriched.add({
          ...Map<String, dynamic>.from(w),
          'sessions_count': summary['sessions_count'] ?? 0,
          'total_minutes': summary['total_minutes'] ?? 0,
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
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text(error!));
    }

    if (workers.isEmpty) {
      return const Center(child: Text('No workers found'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: workers.length,
      itemBuilder: (_, i) {
        final w = workers[i];

        final empId = w['employee_id']?.toString() ?? '';
        final name =
            w['employee_name'] ??
            w['full_name'] ??
            w['name'] ??
            empId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name ($empId)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Day status: ${w['day_status']}'),
                Text('Sessions: ${w['sessions_count']}'),
                Text('Total minutes: ${w['total_minutes']}'),
                if (w['open_task'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Open task: '
                    '${w['open_task']['project_id']} · '
                    '${w['open_task']['task_id']} · '
                    'since ${w['open_task']['start_ts']}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
