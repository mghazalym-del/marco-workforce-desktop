import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../app/app_state.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool loading = true;
  String? error;
  List<dynamic> rows = [];

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
        '/api/v1/monitor/activity/projects',
        query: {'work_date': appState.selectedDateStr},
      );

      final data = (json['data'] as Map<String, dynamic>? ) ?? {};
      rows = (data['items'] as List<dynamic>? ) ?? [];

    } catch (e) {
      error = e.toString();
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(child: Text('Error: $error'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Project')),
            DataColumn(label: Text('Task')),
            DataColumn(label: Text('Workers')),
            DataColumn(label: Text('Accepted')),
            DataColumn(label: Text('Rejected')),
            DataColumn(label: Text('Last Activity')),
          ],
          rows: rows.map<DataRow>((r) {
            final m = r as Map<String, dynamic>;
            return DataRow(cells: [
              DataCell(Text((m['project_id'] ?? '').toString())),
              DataCell(Text((m['task_id'] ?? '').toString())),
              DataCell(Text((m['workers'] ?? 0).toString())),
              DataCell(Text((m['accepted_scans'] ?? 0).toString())),
              DataCell(Text((m['rejected_scans'] ?? 0).toString())),
              DataCell(Text((m['last_scan'] ?? m['last_activity'] ?? '').toString())),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
