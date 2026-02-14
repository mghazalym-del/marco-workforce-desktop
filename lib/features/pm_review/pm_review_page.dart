import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';
import '../supervisors/supervisor_day_workers_page.dart';
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

  bool showOnlyClosed = true;

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
  }

  String _myEmployeeId(AppState app) {
    // Your AppState/profile structure may vary; this is the safest pattern.
    final p = app.profile;
    if (p == null) return '';
    // Try common fields:
    final dynamic mp = p;
    final id = (mp.employeeId ?? mp.employee_id ?? mp['employee_id'] ?? mp['employeeId']);
    return (id ?? '').toString();
  }

  Future<void> _loadSupervisors() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final app = context.read<AppState>();
      final myId = _myEmployeeId(app);
      final myRole = app.role.toUpperCase();

      final json = await widget.api.getJson('/api/v1/admin/supervisors');

      // Support {data:{supervisors:[...]}} or direct {supervisors:[...]}
      Map<String, dynamic> data;
      if (json is Map && json['data'] is Map) {
        data = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json is Map) {
        data = Map<String, dynamic>.from(json as Map);
      } else {
        data = {};
      }

      final list = (data['supervisors'] as List?) ?? const [];
      final all = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // ✅ Hierarchy scoping (data-only):
      // - PM should see supervisors under SEs under PM (requires supervisor_employee_id to be present in supervisors payload)
      // - SE should see supervisors directly under SE (supervisor_employee_id == myId)
      // If payload doesn't contain supervisor_employee_id, we fall back to showing all (safe).
      List<Map<String, dynamic>> scoped = all;

      final hasSupLink = all.any((s) => s.containsKey('supervisor_employee_id'));

      if (hasSupLink && (myRole == 'SE' || myRole == 'PM')) {
        if (myRole == 'SE') {
          scoped = all.where((s) => (s['supervisor_employee_id'] ?? '').toString() == myId).toList();
        } else if (myRole == 'PM') {
          // PM → SE → Supervisor
          // We only have one link field, so we can only scope if supervisors carry their SE id.
          // If later you add endpoints to list SEs under PM, we'll make it exact.
          // For now: show all supervisors that report to ANY SE under this PM IF supervisors payload includes SE id.
          // Since you have only one SE (E9002) now, this works.
          scoped = all.where((s) => (s['supervisor_employee_id'] ?? '').toString() != '').toList();
        }
      }

      // Pick first automatically
      final firstId = scoped.isNotEmpty ? (scoped.first['employee_id'] ?? scoped.first['supervisor_id'])?.toString() : null;

      setState(() {
        supervisors = scoped;
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

    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Error: $error'));

    if (supervisors.isEmpty) {
      return const Center(child: Text('No supervisors available for your scope.'));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Text('Supervisor:', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: selectedSupervisorId,
                items: supervisors.map((s) {
                  final id = (s['employee_id'] ?? s['supervisor_id'] ?? '').toString();
                  final name = (s['full_name'] ?? s['name'] ?? id).toString();
                  return DropdownMenuItem(
                    value: id,
                    child: Text('$name ($id)'),
                  );
                }).toList(),
                onChanged: (v) => setState(() => selectedSupervisorId = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Only CLOSED days'),
                selected: showOnlyClosed,
                onSelected: (v) => setState(() => showOnlyClosed = v),
              ),
              const SizedBox(width: 8),
              Text('Work date: ${app.selectedDateStr}'),
              IconButton(
                tooltip: 'Reload',
                onPressed: _loadSupervisors,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: selectedSupervisorId == null
                ? const Center(child: Text('Select a supervisor'))
                : _ReviewWorkersList(
                    api: widget.api,
                    supervisorId: selectedSupervisorId!,
                    workDate: app.selectedDateStr,
                    showOnlyClosed: showOnlyClosed,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewWorkersList extends StatefulWidget {
  final ApiClient api;
  final String supervisorId;
  final String workDate;
  final bool showOnlyClosed;

  const _ReviewWorkersList({
    required this.api,
    required this.supervisorId,
    required this.workDate,
    required this.showOnlyClosed,
  });

  @override
  State<_ReviewWorkersList> createState() => _ReviewWorkersListState();
}

class _ReviewWorkersListState extends State<_ReviewWorkersList> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> workers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ReviewWorkersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supervisorId != widget.supervisorId || oldWidget.workDate != widget.workDate || oldWidget.showOnlyClosed != widget.showOnlyClosed) {
      _load();
    }
  }

  List<Map<String, dynamic>> _extractWorkers(dynamic json) {
    dynamic v = json;
    if (v is Map && v['data'] != null) v = v['data'];
    if (v is Map && v['workers'] is List) {
      return (v['workers'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      workers = [];
    });

    try {
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': widget.workDate},
      );

      var list = _extractWorkers(json);

      if (widget.showOnlyClosed) {
        list = list.where((w) => (w['day_status'] ?? '').toString().toUpperCase() == 'CLOSED').toList();
      }

      setState(() {
        workers = list;
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
    if (error != null) return Center(child: Text('Error: $error'));
    if (workers.isEmpty) return const Center(child: Text('No workers match this filter/date.'));

    return ListView.separated(
      itemCount: workers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final w = workers[i];
        final empId = (w['employee_id'] ?? '').toString();
        final name = (w['employee_name'] ?? w['full_name'] ?? w['name'] ?? empId).toString();
        final status = (w['day_status'] ?? 'N/A').toString();

        return Card(
          child: ListTile(
            title: Text('$name ($empId)'),
            subtitle: Text('Status: $status'),
            trailing: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PmReviewWorkerDetailPage(
                      api: widget.api,
                      employeeId: empId,
                      workDate: widget.workDate,
                      supervisorId: widget.supervisorId,
                    ),
                  ),
                );
              },
              child: const Text('Review'),
            ),
          ),
        );
      },
    );
  }
}
