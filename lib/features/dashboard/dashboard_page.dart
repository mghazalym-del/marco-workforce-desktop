import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../app/app_state.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool loading = true;
  String? error;
  Map<String, dynamic>? data;

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
      data = null;
    });

    try {
      // ApiClient prefixes /api/v1
      final json = await widget.api.getJson(
        '/monitor/dashboard',
        query: {'work_date': workDate},
      );

      // Support both shapes:
      // - already unwrapped: {work_date, day_counts, scan_counts, top_tasks}
      // - wrapped: {data:{...}}
      Map<String, dynamic> d;
      if (json is Map && json['data'] is Map) {
        d = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json is Map) {
        d = Map<String, dynamic>.from(json as Map);
      } else {
        d = <String, dynamic>{};
      }

      setState(() {
        data = d.isEmpty ? null : d;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Widget _kpi(String title, int value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<dynamic>()
        .map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{})
        .where((m) => m.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Error: $error'));
    if (data == null) return const Center(child: Text('No data for the selected date.'));

    final dayCounts = (data!['day_counts'] is Map)
        ? Map<String, dynamic>.from(data!['day_counts'] as Map)
        : <String, dynamic>{};

    final scanCounts = (data!['scan_counts'] is Map)
        ? Map<String, dynamic>.from(data!['scan_counts'] as Map)
        : <String, dynamic>{};

    final openDays = _asInt(dayCounts['open_days']);
    final closedDays = _asInt(dayCounts['closed_days']);

    final totalScans = _asInt(scanCounts['total_scans']);
    final acceptedScans = _asInt(scanCounts['accepted_scans']);
    final rejectedScans = _asInt(scanCounts['rejected_scans']);
    final offlineScans = _asInt(scanCounts['offline_scans']);

    // backend: top_tasks: [{project_id, task_id, scans}]
    final topTasksRaw = data!['top_tasks'] ?? const [];
    final topTasks = _mapList(topTasksRaw).map((t) {
      return {
        'project_id': (t['project_id'] ?? '').toString(),
        'task_id': (t['task_id'] ?? '').toString(),
        'scans': _asInt(t['scans']),
      };
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => _load(context.read<AppState>().selectedDateStr),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('Open Days', openDays),
              _kpi('Closed Days', closedDays),
              _kpi('Total Scans', totalScans),
              _kpi('Accepted Scans', acceptedScans),
              _kpi('Rejected Scans', rejectedScans),
              _kpi('Offline Scans', offlineScans),
            ],
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top Tasks', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),

                  if (topTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No task activity for the selected date.'),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('project_id')),
                          DataColumn(label: Text('task_id')),
                          DataColumn(label: Text('scans')),
                        ],
                        rows: topTasks.map((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text(r['project_id'].toString())),
                              DataCell(Text(r['task_id'].toString())),
                              DataCell(Text(r['scans'].toString())),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
