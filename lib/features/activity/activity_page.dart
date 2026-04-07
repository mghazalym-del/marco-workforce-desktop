import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../app/app_state.dart';

class ActivityPage extends StatefulWidget {
  final ApiClient api;
  const ActivityPage({super.key, required this.api});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  String _lastWorkDate = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workDate = context.watch<AppState>().selectedDateStr;

    if (workDate != _lastWorkDate) {
      _lastWorkDate = workDate;
      _load(workDate);
    }
  }

  Future<void> _load(String workDate) async {
    setState(() {
      loading = true;
      error = null;
      items = [];
    });

    try {
      final res = await widget.api.getJson(
        '/monitor/activity',
        query: {'work_date': workDate},
      );

      final list = (res['activities'] ?? []) as List;

      setState(() {
        items = list.map((e) => Map<String, dynamic>.from(e)).toList();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    if (status == 'Accepted') return Colors.green;
    return Colors.red;
  }

  String _time(String? ts) {
    if (ts == null) return '-';
    try {
      final d = DateTime.parse(ts).toLocal();
      return "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return ts;
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

    if (items.isEmpty) {
      return const Center(child: Text('No activity for the selected date.'));
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade200,
          child: Row(
            children: const [
              Expanded(flex: 1, child: Text("Time", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text("Worker")),
              Expanded(flex: 2, child: Text("Supervisor")),
              Expanded(flex: 2, child: Text("Task")),
              Expanded(flex: 1, child: Text("Status")),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final m = items[i];

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 1, child: Text(_time(m['scan_timestamp_server']))),

                    Expanded(
                      flex: 2,
                      child: Text(
                        "${m['worker_name'] ?? '-'} (${m['worker_id'] ?? ''})",
                      ),
                    ),

                    Expanded(
                      flex: 2,
                      child: Text(
                        "${m['supervisor_name'] ?? '-'} (${m['supervisor_id'] ?? ''})",
                      ),
                    ),

                    Expanded(
                      flex: 2,
                      child: Text(
                        "${m['task_code'] ?? ''} ${m['task_name'] ?? ''}",
                      ),
                    ),

                    Expanded(
                      flex: 1,
                      child: Text(
                        m['scan_status'] ?? '-',
                        style: TextStyle(
                          color: _statusColor(m['scan_status']),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}