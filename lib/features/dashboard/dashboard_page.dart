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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final json = await widget.api.getJson(
        '/api/v1/monitor/dashboard',
        query: {'work_date': appState.selectedDateStr},
      );
      data = json['data'] as Map<String, dynamic>?;
    } catch (e) {
      error = e.toString();
    } finally {
      setState(() => loading = false);
    }
  }

  Widget _kpi(String title, dynamic value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              value.toString(),
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleTable(String title, List<dynamic> rows,
      List<String> columns) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: columns
                    .map((c) => DataColumn(label: Text(c)))
                    .toList(),
                rows: rows.map<DataRow>((r) {
                  final map = r as Map<String, dynamic>;
                  return DataRow(
                    cells: columns
                        .map((c) =>
                            DataCell(Text((map[c] ?? '').toString())))
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text('Error: $error'));
    }

    if (data == null) {
      return const Center(child: Text('No data'));
    }

    final summary = data!['summary'] ?? {};
    final projects = data!['projects'] ?? [];
    final tasks = data!['tasks'] ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('Open Days', summary['open_days'] ?? 0),
              _kpi('Closed Days', summary['closed_days'] ?? 0),
              _kpi('Accepted Scans', summary['accepted_scans'] ?? 0),
              _kpi('Rejected Scans', summary['rejected_scans'] ?? 0),
              _kpi('Offline Scans', summary['offline_scans'] ?? 0),
            ],
          ),
          const SizedBox(height: 16),
          _simpleTable(
            'Top Projects',
            projects,
            ['project_id', 'workers', 'accepted', 'rejected'],
          ),
          const SizedBox(height: 16),
          _simpleTable(
            'Top Tasks',
            tasks,
            ['task_id', 'workers', 'accepted', 'rejected'],
          ),
        ],
      ),
    );
  }
}
