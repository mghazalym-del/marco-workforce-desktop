import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class SeTaskControlPage extends StatefulWidget {
  final ApiClient api;
  const SeTaskControlPage({super.key, required this.api});

  @override
  State<SeTaskControlPage> createState() => _SeTaskControlPageState();
}

class _SeTaskControlPageState extends State<SeTaskControlPage> {
  bool _loading = true;
  String? _error;
  String _search = '';

  List<Map<String, dynamic>> _rows = [];

  String _safe(dynamic v) => (v ?? '').toString();

  String get _myEmployeeId =>
      (context.read<AppState>().profile?.employeeId ?? '').trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myId = _myEmployeeId;

    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
    });

    try {
      final projectsRes = await widget.api.getJson('/projects');

      List<Map<String, dynamic>> projects = [];
      if (projectsRes is Map && projectsRes['projects'] is List) {
        projects = (projectsRes['projects'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (projectsRes is List) {
        projects = projectsRes
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      final rows = <Map<String, dynamic>>[];

      for (final p in projects) {
        final projectCode = _safe(p['project_code']);
        if (projectCode.isEmpty) continue;

        final treeRes = await widget.api.getJson('/projects/$projectCode/tree');

        List<Map<String, dynamic>> items = [];
        if (treeRes is Map && treeRes['items'] is List) {
          items = (treeRes['items'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else if (treeRes is List) {
          items = treeRes
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }

        for (final item in items) {
          final assignedTo = _safe(item['assigned_to_employee_id']).trim();

          // only tasks assigned to logged-in SE
          if (assignedTo != myId) continue;

          final taskCode = _safe(item['item_code']);
          final taskName = _safe(item['name']);
          final status = _safe(item['task_status']);
          final assignedAt = _safe(item['assigned_at']);
          final activatedAt = _safe(item['activated_at']);

          List<Map<String, dynamic>> releases = [];
          try {
            final relRes = await widget.api.getJson(
              '/task-releases/by-task',
              query: {
                'project_id': projectCode,
                'task_id': taskCode,
              },
            );

            if (relRes is List) {
              releases = relRes
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            } else if (relRes is Map && relRes['data'] is List) {
              releases = (relRes['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          } catch (_) {
            // keep row even if release lookup fails
          }

          final activeReleases = releases.where((r) {
            return _safe(r['release_status']).toUpperCase() == 'ACTIVE';
          }).toList();

          final supervisors = activeReleases.map((r) {
            final supId = _safe(r['supervisor_employee_id']);
            final supName = _safe(r['supervisor_name']);
            return supName.isEmpty ? supId : '$supId — $supName';
          }).toSet().toList()
            ..sort();

          rows.add({
            'project': projectCode,
            'task_code': taskCode,
            'task_name': taskName,
            'status': status,
            'assigned_se': assignedTo,
            'assigned_at': assignedAt,
            'activated_at': activatedAt,
            'supervisors': supervisors,
            'active_release_count': activeReleases.length,
          });
        }
      }

      rows.sort((a, b) {
        final ap = _safe(a['project']);
        final bp = _safe(b['project']);
        final at = _safe(a['task_code']);
        final bt = _safe(b['task_code']);
        final cmp = ap.compareTo(bp);
        if (cmp != 0) return cmp;
        return at.compareTo(bt);
      });

      setState(() {
        _rows = rows;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _rows;

    return _rows.where((r) {
      final values = [
        _safe(r['project']),
        _safe(r['task_code']),
        _safe(r['task_name']),
        _safe(r['status']),
        ...((r['supervisors'] as List?) ?? []).map((e) => e.toString()),
      ];
      return values.any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  void _showDetails(Map<String, dynamic> row) {
    final supervisors =
        ((row['supervisors'] as List?) ?? []).map((e) => e.toString()).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${row['project']} / ${row['task_code']}"),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Task Name: ${row['task_name']}"),
                const SizedBox(height: 8),
                Text("Status: ${row['status']}"),
                const SizedBox(height: 8),
                Text("Assigned SE: ${row['assigned_se']}"),
                const SizedBox(height: 8),
                Text("Activated At: ${_safe(row['activated_at']).isEmpty ? "-" : row['activated_at']}"),
                const SizedBox(height: 8),
                Text("Assigned At: ${_safe(row['assigned_at']).isEmpty ? "-" : row['assigned_at']}"),
                const SizedBox(height: 12),
                Text(
                  "Supervisors with ACTIVE releases (${row['active_release_count']})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (supervisors.isEmpty)
                  const Text("No active supervisor releases.")
                else
                  ...supervisors.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text("• $s"),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final assignedCount = _rows.length;
    final releasedCount = _rows
        .where((r) => (_safe(r['active_release_count']) != '0'))
        .length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SE Task Control',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryCard('My Assigned Tasks', assignedCount.toString()),
              const SizedBox(width: 12),
              _summaryCard('Tasks With Releases', releasedCount.toString()),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search project / task / supervisor',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : rows.isEmpty
                        ? const Center(child: Text("No tasks assigned to you"))
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.06),
                              ),
                            ),
                            child: ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final r = rows[i];
                                final supervisors = (r['supervisors'] as List?) ?? [];

                                return ListTile(
                                  title: Text(
                                    "${r['project']} / ${r['task_code']} — ${r['task_name']}",
                                  ),
                                  subtitle: Text(
                                    "Status: ${r['status']}   •   "
                                    "Supervisors: ${supervisors.length}",
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showDetails(r),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}