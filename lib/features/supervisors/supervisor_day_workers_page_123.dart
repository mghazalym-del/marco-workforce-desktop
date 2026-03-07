import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class SupervisorDayWorkersPage extends StatefulWidget {
  final ApiClient api;
  final String supervisorId;
  final String workDate;
  final VoidCallback? onDataChanged;

  const SupervisorDayWorkersPage({
    super.key,
    required this.api,
    required this.supervisorId,
    required this.workDate,
    this.onDataChanged,
  });

  @override
  State<SupervisorDayWorkersPage> createState() => _SupervisorDayWorkersPageState();
}

class _SupervisorDayWorkersPageState extends State<SupervisorDayWorkersPage> {
  String _dateOnly(String s) {
    if (s.isEmpty) return s;
    return (s.length >= 10) ? s.substring(0, 10) : s;
  }

  String get _workDate => _dateOnly(widget.workDate);


  bool loading = false;
  String? error;

  List<Map<String, dynamic>> rows = [];

  // per-worker action busy flags
  final Set<String> busyIds = {};

  bool _headerBusy = false;

  // --- backend endpoints helpers ---
  Future<dynamic> _tryPostJson(List<String> paths, {required Map<String, dynamic> body}) async {
    dynamic lastErr;
    for (final p in paths) {
      try {
        return await widget.api.postJson(p, body: body);
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('All endpoint variants failed');
  }

  // Supervisor operational actions (existing)
  List<String> _closeDayPaths() => const [
        '/api/v1/supervisor/close-day',
        '/api/v1/supervisor/close_day',
        '/api/v1/supervisor/closeDay',
        '/api/v1/supervisor/day/close',
        '/api/v1/supervisor/days/close',
      ];

  List<String> _closeOpenTaskPaths() => const [
        '/api/v1/supervisor/close-open-task',
        '/api/v1/supervisor/close_open_task',
        '/api/v1/supervisor/closeOpenTask',
        '/api/v1/supervisor/open-task/close',
        '/api/v1/supervisor/open_task/close',
      ];

  // SE/PM review actions (Finalize / Return)
  List<String> _finalizeSupervisorDayPaths() => const [
        // preferred (clean separation) if you add se.js
        '/api/v1/se/supervisors/{SUP}/finalize-day',
        // existing backend route
        '/api/v1/supervisor/finalize-supervisor-day',
      ];

List<String> _returnWorkerDayPaths(String supervisorId, String workerId) => [
      '/api/v1/se/supervisors/$supervisorId/workers/$workerId/return-day',
    ];

List<String> _finalizeWorkerDayPaths(String supervisorId, String workerId) => [
      '/api/v1/se/supervisors/$supervisorId/workers/$workerId/finalize-day',
    ];

  List<String> _returnSupervisorDayPaths() => const [
        // preferred (clean separation) if you add se.js
        '/api/v1/se/supervisors/{SUP}/return-day',
        // optional future alias
        '/api/v1/supervisor/return-supervisor-day',
      ];

  String _roleUpper(AppState app) => (app.role).toUpperCase();
// Visual status system (SE quick scan)
// OPEN 🟡  CLOSED 🔵  RETURNED 🟠  FINALIZED 🟢
Color _statusColor(String status) {
  final s = status.toUpperCase();
  switch (s) {
    case 'OPEN':
      return Colors.amber; // 🟡
    case 'CLOSED':
      return Colors.blue; // 🔵
    case 'RETURNED':
      return Colors.deepOrange; // 🟠
    case 'FINALIZED':
      return Colors.green; // 🟢
    default:
      return Colors.grey;
  }
}

Widget _statusPill(String status) {
  final c = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.withOpacity(0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(status.toUpperCase(), style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

  bool _isSEPM(String role) => role == 'SE' || role == 'PM';
  bool _isSupervisorRole(String role) => role == 'ADMIN' || role == 'SUPERVISOR';

  // --- JSON helpers ---
  List<Map<String, dynamic>> _extractWorkers(dynamic json) {
    if (json is! Map) return const [];

    // api.getJson() may return:
    // A) { success: true, data: { workers: [...] } }
    // B) { supervisor_id:..., work_date:..., workers: [...] }   (already-unwrapped data)
    final dynamic data = (json['data'] is Map) ? json['data'] : json;

    if (data is! Map) return const [];

    final dynamic list = data['workers'];

    if (list is List) {
      return list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    return const [];
  }


  // --- load ---
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant SupervisorDayWorkersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supervisorId != widget.supervisorId || oldWidget.workDate != widget.workDate) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      rows = [];
    });

    try {
      final app = context.read<AppState>();
      final role = _roleUpper(app);

      // Base list: workers + day_status (from monitor always)
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': _workDate},
      );

      final baseWorkers = _extractWorkers(json);

      // Enrich each worker with assignments/day/summary (sessions_count, total_minutes, open_task)
      // Also allow SE to view correct counts (requires backend access for assignments summary).
      final enriched = await Future.wait(baseWorkers.map((w) async {
        final empId = (w['employee_id'] ?? '').toString();

        Map<String, dynamic> summary = {};
        try {
          final s = await widget.api.getJson(
            '/api/v1/assignments/day/summary/$empId',
            query: {'work_date': _workDate},
          );

          // support {success,data:{...}} OR direct {...}
          if (s is Map && s['data'] is Map) {
            summary = Map<String, dynamic>.from(s['data'] as Map);
          } else if (s is Map) {
            summary = Map<String, dynamic>.from(s);
          }
        } catch (_) {
          // don’t fail the whole page if one worker summary fails
        }

        return <String, dynamic>{
          ...w,
          'sessions_count': summary['sessions_count'] ?? 0,
          'total_minutes': summary['total_minutes'] ?? 0,
          'open_task': summary['open_task'], // Map or null
          '_role': role,
        };
      }).toList());

      setState(() {
        rows = enriched;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  // --- actions ---
  Future<void> _closeOpenTask({
    required String employeeId,
    required Map<String, dynamic>? openTask,
  }) async {
    if (busyIds.contains(employeeId)) return;
    if (openTask == null) return;

    setState(() => busyIds.add(employeeId));
    try {
      final body = <String, dynamic>{
        'employee_id': employeeId,
        'work_date': widget.workDate,
        // open_task may contain project_id/task_id/start_ts
        'project_id': openTask['project_id'],
        'task_id': openTask['task_id'],
        'start_ts': openTask['start_ts'],
      };

      await _tryPostJson(_closeOpenTaskPaths(), body: body);

      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _toast('Close open task failed: $e');
    } finally {
      setState(() => busyIds.remove(employeeId));
    }
  }

  Future<void> _closeDay({required String employeeId}) async {
    if (busyIds.contains(employeeId)) return;

    setState(() => busyIds.add(employeeId));
    try {
      final body = <String, dynamic>{
        'employee_id': employeeId,
        'work_date': widget.workDate,
      };

      await _tryPostJson(_closeDayPaths(), body: body);

      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _toast('Close day failed: $e');
    } finally {
      setState(() => busyIds.remove(employeeId));
    }
  }

  Future<void> _finalizeSupervisorDay() async {
    if (_headerBusy) return;
    setState(() => _headerBusy = true);

    try {
      // prefer /api/v1/se/... if present, else fallback to /api/v1/supervisor/finalize-supervisor-day
      final paths = _finalizeSupervisorDayPaths()
          .map((p) => p.replaceAll('{SUP}', widget.supervisorId))
          .toList();

      // body differs by endpoint:
      // - se endpoint expects {work_date}
      // - supervisor endpoint expects {supervisor_id, work_date}
      dynamic res;
      try {
        res = await widget.api.postJson(paths.first, body: {'work_date': widget.workDate});
      } catch (_) {
        res = await widget.api.postJson(paths.last, body: {'supervisor_id': widget.supervisorId, 'work_date': widget.workDate});
      }

      _toast('Finalized: ${res is Map ? (res['data'] ?? '') : ''}');
      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _toast('Finalize failed: $e');
    } finally {
      setState(() => _headerBusy = false);
    }
  }

  Future<void> _returnSupervisorDay() async {
    if (_headerBusy) return;
    setState(() => _headerBusy = true);

    try {
      final paths = _returnSupervisorDayPaths().map((p) => p.replaceAll('{SUP}', widget.supervisorId)).toList();
      // Only se endpoint is defined in our plan; if missing, show a clear message.
      await widget.api.postJson(paths.first, body: {'work_date': widget.workDate});
      _toast('Returned to Supervisor');
      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _toast('Return failed (endpoint may not exist yet): $e');
    } finally {
      setState(() => _headerBusy = false);
    }
  }

Future<void> _returnWorkerDay(String workerId, String dayStatus) async {
  final role = _roleUpper(context.read<AppState>());
  if (role != 'SE') return;

  if (dayStatus.toUpperCase() != 'CLOSED') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Return is enabled only for CLOSED worker days.')),
    );
    return;
  }

  setState(() => _busyIds.add('return:$workerId'));
  try {
    await _postRoleAware(
      paths: _returnWorkerDayPaths(widget.supervisorId, workerId),
      query: {'work_date': _workDate},
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Returned worker day ($workerId) to supervisor.')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Return worker failed: $e')),
    );
  } finally {
    if (mounted) setState(() => _busyIds.remove('return:$workerId'));
  }
}

Future<void> _finalizeWorkerDay(String workerId, String dayStatus, Map<String, dynamic>? openTask) async {
  final role = _roleUpper(context.read<AppState>());
  if (role != 'SE') return;

  if (dayStatus.toUpperCase() != 'CLOSED') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Finalize requires CLOSED worker day.')),
    );
    return;
  }
  if (openTask != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cannot finalize while an open task exists.')),
    );
    return;
  }

  setState(() => _busyIds.add('finalize:$workerId'));
  try {
    await _postRoleAware(
      paths: _finalizeWorkerDayPaths(widget.supervisorId, workerId),
      query: {'work_date': _workDate},
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Finalized worker day ($workerId).')),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Finalize worker failed: $e')),
    );
  } finally {
    if (mounted) setState(() => _busyIds.remove('finalize:$workerId'));
  }
}

  Future<void> _showWorkerDetails(String employeeId, String fullName) async {
    try {
      final json = await widget.api.getJson(
        '/api/v1/monitor/worker/$employeeId/day',
        query: {'work_date': _workDate},
      );

      Map<String, dynamic> data = {};
      if (json is Map && json['data'] is Map) data = Map<String, dynamic>.from(json['data'] as Map);
      final sessions = (data['sessions'] is List) ? (data['sessions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      final scans = (data['scans'] is List) ? (data['scans'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text('$employeeId — $fullName (${widget.workDate})'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sessions', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (sessions.isEmpty) const Text('No sessions'),
                    for (final s in sessions) ...[
                      Text('• ${s['project_id']} / ${s['task_id']}  |  start: ${s['start_ts']}  end: ${s['end_ts'] ?? '-'}  |  min: ${s['duration_minutes'] ?? 0}  |  status: ${s['status']}'),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 12),
                    const Text('Scans', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (scans.isEmpty) const Text('No scans'),
                    for (final sc in scans) ...[
                      Text('• ${sc['project_id']} / ${sc['task_id']}  |  status: ${sc['scan_status'] ?? sc['status'] ?? ''}  |  ts: ${sc['created_at'] ?? sc['scan_ts'] ?? ''}'),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ],
          );
        },
      );
    } catch (e) {
      _toast('Details failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = _roleUpper(app);
    final seMode = _isSEPM(role);
    final supervisorMode = _isSupervisorRole(role);

    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Error: $error'));
    if (rows.isEmpty) return const Center(child: Text('No workers found.'));

    // Header actions:
    // - SE/PM: finalize / return for the whole supervisor day
    // - Supervisor: informational header only (actions per worker)
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Work date: ${widget.workDate}  |  Supervisor: ${widget.supervisorId}  |  Role: $role',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_headerBusy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              if (seMode) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _headerBusy ? null : _returnSupervisorDay,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Return to Supervisor'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _headerBusy ? null : _finalizeSupervisorDay,
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Finalize Supervisor Day'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final w = rows[i];
              final empId = (w['employee_id'] ?? '').toString();
              final fullName = (w['full_name'] ?? '').toString();
              final dayStatus = (w['day_status'] ?? '').toString().toUpperCase();

              final sessionsCount = w['sessions_count'] ?? 0;
              final totalMinutes = w['total_minutes'] ?? 0;
              final openTask = w['open_task'];

              final busy = busyIds.contains(empId);

              // Rules:
              // - Supervisor can close-open-task if open_task exists
              // - Supervisor can close day only if OPEN and no open_task
              final canCloseOpenTask = supervisorMode && openTask != null && dayStatus == 'OPEN' && !busy;
              final canCloseDay = supervisorMode && dayStatus == 'OPEN' && openTask == null && !busy;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$empId — $fullName',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          _statusPill(dayStatus),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Details',
                            onPressed: () => _showWorkerDetails(empId, fullName),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          Text('Sessions: $sessionsCount'),
                          Text('Minutes: $totalMinutes'),
                          Text('Open task: ${openTask == null ? '-' : '${openTask['project_id']}/${openTask['task_id']}'}'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Actions row (Supervisor only)
                      if (supervisorMode) Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: canCloseOpenTask ? () => _closeOpenTask(employeeId: empId, openTask: (openTask is Map) ? Map<String, dynamic>.from(openTask) : null) : null,
                            icon: const Icon(Icons.task_alt, size: 18),
                            label: const Text('Close Open Task'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: canCloseDay ? () => _closeDay(employeeId: empId) : null,
                            icon: const Icon(Icons.lock, size: 18),
                            label: const Text('Close Day'),
                          ),
                          if (busy) ...[
                            const SizedBox(width: 10),
                            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          ],
                        ],
                      ),
                      if (seMode) ...[
                        const SizedBox(height: 6),
                        Row(
  children: [
    Expanded(
      child: OutlinedButton.icon(
        onPressed: (_busyIds.contains('return:$employeeId') || dayStatus.toUpperCase() != 'CLOSED')
            ? null
            : () => _returnWorkerDay(employeeId, dayStatus),
        icon: const Icon(Icons.keyboard_return),
        label: const Text('Return Worker Day'),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: ElevatedButton.icon(
        onPressed: (_busyIds.contains('finalize:$employeeId') ||
                dayStatus.toUpperCase() != 'CLOSED' ||
                openTask != null)
            ? null
            : () => _finalizeWorkerDay(employeeId, dayStatus, openTask),
        icon: const Icon(Icons.verified),
        label: const Text('Finalize Worker Day'),
      ),
    ),
  ],
),
const SizedBox(height: 6),

Text(
                          'SE/PM Review mode: use Finalize/Return at the top after checking details.',
                          style: TextStyle(color: Colors.black.withOpacity(0.55)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
