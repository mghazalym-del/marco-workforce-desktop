import 'package:flutter/material.dart';
import '../../api/api_client.dart';

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
  bool loading = true;
  String? error;

  // Each row contains:
  // employee_id, employee_name, day_status + enriched sessions_count/total_minutes/open_task
  List<Map<String, dynamic>> rows = [];

  final Set<String> busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _extractWorkers(dynamic json) {
    dynamic v = json;
    if (v is Map && v['data'] != null) v = v['data'];

    if (v is Map && v['workers'] is List) {
      return (v['workers'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      rows = [];
    });

    try {
      // Base list: workers + day_status (from monitor)
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/${widget.supervisorId}/workers',
        query: {'work_date': widget.workDate},
      );

      final baseWorkers = _extractWorkers(json);

      // Enrich each worker with assignments/day/summary (sessions_count, total_minutes, open_task)
      final enriched = await Future.wait(baseWorkers.map((w) async {
        final empId = (w['employee_id'] ?? '').toString();

        Map<String, dynamic> summary = {};
        try {
          final s = await widget.api.getJson(
            '/api/v1/assignments/day/summary/$empId',
            query: {'work_date': widget.workDate},
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

  Future<bool> _confirm({
    required String title,
    required String message,
    String okText = 'Confirm',
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(okText)),
        ],
      ),
    );
    return res == true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<dynamic> _postWithFallback(List<String> paths, Map<String, dynamic> body) async {
    Object? lastErr;

    for (final p in paths) {
      try {
        // IMPORTANT: print every attempt so we can lock the correct path quickly
        // ignore: avoid_print
        print('TRY POST => $p  body=$body');

        final res = await widget.api.postJson(p, body: body);

        // ignore: avoid_print
        print('POST OK  => $p  res=$res');

        return res;
      } catch (e) {
        // ignore: avoid_print
        print('POST FAIL=> $p  err=$e');
        lastErr = e;
      }
    }

    throw lastErr ?? Exception('All endpoint variants failed');
  }

  // Expanded candidate list (mobile is using one of these)
  List<String> _closeDayPaths() => const [
        // Most common
        '/api/v1/supervisor/close-day',
        '/api/v1/supervisor/close_day',
        '/api/v1/supervisor/closeDay',

        // Often used patterns
        '/api/v1/supervisor/day/close',
        '/api/v1/supervisor/days/close',
        '/api/v1/supervisor/work-day/close',
        '/api/v1/supervisor/workday/close',

        // Some teams use actions folder style
        '/api/v1/supervisor/actions/close-day',
        '/api/v1/supervisor/actions/closeDay',
      ];

  List<String> _closeOpenTaskPaths() => const [
        '/api/v1/supervisor/close-open-task',
        '/api/v1/supervisor/close_open_task',
        '/api/v1/supervisor/closeOpenTask',

        '/api/v1/supervisor/open-task/close',
        '/api/v1/supervisor/open_task/close',
        '/api/v1/supervisor/task/close-open',
        '/api/v1/supervisor/tasks/close-open',

        '/api/v1/supervisor/actions/close-open-task',
        '/api/v1/supervisor/actions/closeOpenTask',
      ];

  Future<void> _closeOpenTask({
    required String employeeId,
    required Map<String, dynamic>? openTask,
  }) async {
    if (busyIds.contains(employeeId)) return;

    final ok = await _confirm(
      title: 'Close Open Task',
      message: 'Close the open task for $employeeId on ${widget.workDate}?',
      okText: 'Close Task',
    );
    if (!ok) return;

    setState(() => busyIds.add(employeeId));

    try {
      final payload = <String, dynamic>{
        'employee_id': employeeId,
        'work_date': widget.workDate,
      };

      // Provide hints if backend expects them
      if (openTask != null) {
        if (openTask['project_id'] != null) payload['project_id'] = openTask['project_id'];
        if (openTask['task_id'] != null) payload['task_id'] = openTask['task_id'];
        if (openTask['session_id'] != null) payload['session_id'] = openTask['session_id'];
      }

      await _postWithFallback(_closeOpenTaskPaths(), payload);

      _snack('Open task closed for $employeeId');
      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _snack('Failed to close open task: $e');
    } finally {
      if (mounted) setState(() => busyIds.remove(employeeId));
    }
  }

  Future<void> _closeDay({
    required String employeeId,
  }) async {
    if (busyIds.contains(employeeId)) return;

    final ok = await _confirm(
      title: 'Close Day',
      message:
          'Close the day for $employeeId on ${widget.workDate}?\n\nThis will move the day to supervisor close (pending SE/PM review later).',
      okText: 'Close Day',
    );
    if (!ok) return;

    setState(() => busyIds.add(employeeId));

    try {
      final payload = <String, dynamic>{
        'employee_id': employeeId,
        'work_date': widget.workDate,
      };

      await _postWithFallback(_closeDayPaths(), payload);

      _snack('Day closed for $employeeId');
      await _load();
      widget.onDataChanged?.call();
    } catch (e) {
      _snack('Failed to close day: $e');
    } finally {
      if (mounted) setState(() => busyIds.remove(employeeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Error: $error'));
    if (rows.isEmpty) return const Center(child: Text('No workers found'));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final w = rows[i];

        final id = (w['employee_id'] ?? '').toString();
        final name = (w['employee_name'] ?? w['full_name'] ?? w['name'] ?? id).toString();

        final dayStatus = (w['day_status'] ?? 'N/A').toString();

        final sessions = (w['sessions_count'] ?? 0).toString();
        final minutes = (w['total_minutes'] ?? 0).toString();

        final openTaskDyn = w['open_task'];
        final hasOpenTask = openTaskDyn != null && openTaskDyn is Map;
        final openTask = hasOpenTask ? Map<String, dynamic>.from(openTaskDyn as Map) : null;

        final isBusy = busyIds.contains(id);
        final canCloseDay = dayStatus.toUpperCase() == 'OPEN' && !hasOpenTask;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$name ($id)', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Day status: $dayStatus'),
              Text('Sessions: $sessions'),
              Text('Total minutes: $minutes'),
              const SizedBox(height: 6),
              if (hasOpenTask)
                Text(
                  'Open task: ${openTask?['project_id'] ?? '-'} · ${openTask?['task_id'] ?? '-'} · since ${openTask?['since'] ?? openTask?['start_ts'] ?? '-'}',
                  style: const TextStyle(color: Colors.red),
                )
              else
                const Text('Open task: -'),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (hasOpenTask)
                    ElevatedButton(
                      onPressed: isBusy ? null : () => _closeOpenTask(employeeId: id, openTask: openTask),
                      child: isBusy
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Close Open Task'),
                    ),
                  if (hasOpenTask) const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (!isBusy && canCloseDay) ? () => _closeDay(employeeId: id) : null,
                    child: isBusy
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Close Day'),
                  ),
                ],
              ),
              if (!canCloseDay && dayStatus.toUpperCase() == 'OPEN' && hasOpenTask)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'You must close the open task before closing the day.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
