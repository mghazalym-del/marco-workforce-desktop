import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';
import 'pm_review_worker_detail_page.dart';

class PmReviewPage extends StatefulWidget {
  final ApiClient api;
  const PmReviewPage({super.key, required this.api});

  @override
  State<PmReviewPage> createState() => _PmReviewPageState();
}

class _PmReviewPageState extends State<PmReviewPage> {
  bool loading = true;
  String? error;

  List<Map<String, dynamic>> supervisors = [];
  String? selectedSupervisorId;

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
  }

  List<Map<String, dynamic>> _extractList(dynamic json, {required String dataKey}) {
    if (json is Map && json['data'] is Map) {
      final data = json['data'] as Map;
      final list = data[dataKey];
      if (list is List) return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (json is Map) {
      final list = json[dataKey];
      if (list is List) return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<void> _loadSupervisors() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      // ✅ IMPORTANT: use monitor endpoint (admin endpoint is forbidden for SE/PM)
      final json = await widget.api.getJson('/api/v1/monitor/supervisors');
      final list = _extractList(json, dataKey: 'supervisors');

      String? firstId;
      if (list.isNotEmpty) {
        firstId = (list.first['employee_id'] ?? list.first['supervisor_id'])?.toString();
      }

      setState(() {
        supervisors = list;
        selectedSupervisorId = selectedSupervisorId ?? firstId;
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
    final app = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PM Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedSupervisorId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor',
                    border: OutlineInputBorder(),
                  ),
                  items: supervisors.map((s) {
                    final id = (s['employee_id'] ?? s['supervisor_id'] ?? '').toString();
                    final name = (s['full_name'] ?? s['name'] ?? 'Supervisor').toString();
                    return DropdownMenuItem(
                      value: id.isEmpty ? null : id,
                      child: Text('$id — $name'),
                    );
                  }).where((i) => i.value != null).toList(),
                  onChanged: (v) => setState(() => selectedSupervisorId = v),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadSupervisors,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (loading) const LinearProgressIndicator(),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Error: $error')),

          const SizedBox(height: 12),

          Expanded(
            child: _buildList(app.workDate),
          ),
        ],
      ),
    );
  }

  Widget _buildList(String workDate) {
    final supId = selectedSupervisorId;
    if (supId == null || supId.isEmpty) {
      return const Center(child: Text('Select a supervisor.'));
    }

    return FutureBuilder<dynamic>(
      future: widget.api.getJson(
        '/api/v1/monitor/supervisors/$supId/workers',
        query: {'work_date': workDate},
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }

        final json = snap.data;
        final workers = _extractList(json, dataKey: 'workers');

        if (workers.isEmpty) {
          return const Center(child: Text('No workers found.'));
        }

        return ListView.separated(
          itemCount: workers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final w = workers[i];
            final empId = (w['employee_id'] ?? w['worker_id'] ?? '').toString();
            final name = (w['full_name'] ?? w['name'] ?? empId).toString();

            return Card(
              child: ListTile(
                title: Text('$empId — $name'),
                subtitle: Text('Tap to view day details for $workDate'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PmReviewWorkerDetailPage(
                        api: widget.api,
                        employeeId: empId,
                        workDate: workDate,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
