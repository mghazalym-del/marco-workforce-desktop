import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class PmTaskControlPage extends StatefulWidget {
  final ApiClient api;
  const PmTaskControlPage({super.key, required this.api});

  @override
  State<PmTaskControlPage> createState() => _PmTaskControlPageState();
}

class _PmTaskControlPageState extends State<PmTaskControlPage> {
  bool _loading = true;
  String? _error;
  String _search = '';

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _safe(dynamic v) => (v ?? '').toString();

  Future<void> _load() async {
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
      } else if (projectsRes is Map && projectsRes['data'] is Map) {
        final data = Map<String, dynamic>.from(projectsRes['data']);
        if (data['projects'] is List) {
          projects = (data['projects'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      final rows = <Map<String, dynamic>>[];

      for (final p in projects) {
        final projectCode = _safe(p['project_code']);
        if (projectCode.isEmpty) continue;

        final treeRes = await widget.api.getJson('/projects/$projectCode/tree');

        Map<String, dynamic> data = {};
        if (treeRes is Map && treeRes['items'] is List) {
          data = Map<String, dynamic>.from(treeRes);
        } else if (treeRes is Map && treeRes['data'] is Map) {
          data = Map<String, dynamic>.from(treeRes['data']);
        }

        final items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        for (final item in items) {
          final taskStatus = _safe(item['task_status']).toUpperCase();
          if (taskStatus != 'ACTIVE' && taskStatus != 'ASSIGNED') {
            continue;
          }

          final taskCode = _safe(item['item_code']);
          final taskName = _safe(item['name']);
          final assignedSe = _safe(item['assigned_to_employee_id']);
          final assignedAt = _safe(item['assigned_at']);
          final activatedAt = _safe(item['activated_at']);

          int releaseCount = 0;
          final supervisors = <String>{};

          try {
            final relRes = await widget.api.getJson(
              '/task-releases/by-task',
              query: {
                'project_id': projectCode,
                'task_id': taskCode,
              },
            );

            List<Map<String, dynamic>> releases = [];
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

            final activeReleases = releases.where((r) {
              return _safe(r['release_status']).toUpperCase() == 'ACTIVE';
            }).toList();

            releaseCount = activeReleases.length;
            for (final r in activeReleases) {
              final supId = _safe(r['supervisor_employee_id']);
              final supName = _safe(r['supervisor_name']);
              if (supId.isNotEmpty) {
                supervisors.add(
                  supName.isEmpty ? supId : '$supId — $supName',
                );
              }
            }
          } catch (_) {
            // keep row even if releases fail
          }

          rows.add({
            'project_code': projectCode,
            'task_code': taskCode,
            'task_name': taskName,
            'task_status': taskStatus,
            'assigned_se': assignedSe,
            'assigned_at': assignedAt,
            'activated_at': activatedAt,
            'active_release_count': releaseCount,
            'supervisors': supervisors.toList()..sort(),
          });
        }
      }

      rows.sort((a, b) {
        final ap = _safe(a['project_code']);
        final bp = _safe(b['project_code']);
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
        _safe(r['project_code']),
        _safe(r['task_code']),
        _safe(r['task_name']),
        _safe(r['task_status']),
        _safe(r['assigned_se']),
        ...((r['supervisors'] as List?) ?? []).map((e) => e.toString()),
      ];
      return values.any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  void _showTaskDrilldown(Map<String, dynamic> row) {
    final supervisors =
        ((row['supervisors'] as List?) ?? []).map((e) => e.toString()).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          '${row['project_code']} / ${row['task_code']}',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task Name: ${row['task_name']}'),
                const SizedBox(height: 8),
                Text('Status: ${row['task_status']}'),
                const SizedBox(height: 8),
                Text('Assigned SE: ${_safe(row['assigned_se']).isEmpty ? "-" : row['assigned_se']}'),
                const SizedBox(height: 8),
                Text('Activated At: ${_safe(row['activated_at']).isEmpty ? "-" : row['activated_at']}'),
                const SizedBox(height: 8),
                Text('Assigned At: ${_safe(row['assigned_at']).isEmpty ? "-" : row['assigned_at']}'),
                const SizedBox(height: 12),
                Text(
                  'Supervisors with ACTIVE releases (${row['active_release_count']})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (supervisors.isEmpty)
                  const Text('No active supervisor releases.')
                else
                  ...supervisors.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $s'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value) {
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
    final activeCount =
        _rows.where((r) => _safe(r['task_status']).toUpperCase() == 'ACTIVE').length;
    final assignedCount =
        _rows.where((r) => _safe(r['task_status']).toUpperCase() == 'ASSIGNED').length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PM Task Control',
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
              _buildSummaryCard('Visible Tasks', _rows.length.toString()),
              const SizedBox(width: 12),
              _buildSummaryCard('Active', activeCount.toString()),
              const SizedBox(width: 12),
              _buildSummaryCard('Assigned', assignedCount.toString()),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search project / task / SE / supervisor',
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
                        ? const Center(child: Text('No PM task rows found.'))
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
                                final row = rows[i];
                                final assignedSe = _safe(row['assigned_se']);
                                final releases = row['active_release_count'];

                                return ListTile(
                                  title: Text(
                                    '${row['project_code']} / ${row['task_code']} — ${row['task_name']}',
                                  ),
                                  subtitle: Text(
                                    'Status: ${row['task_status']}   •   '
                                    'Assigned SE: ${assignedSe.isEmpty ? "-" : assignedSe}   •   '
                                    'Active Releases: $releases',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showTaskDrilldown(row),
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