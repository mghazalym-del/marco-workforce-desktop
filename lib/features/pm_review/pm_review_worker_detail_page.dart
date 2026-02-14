import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class PmReviewWorkerDetailPage extends StatefulWidget {
  final ApiClient api;
  final String employeeId;
  final String workDate;
  final String supervisorId;

  const PmReviewWorkerDetailPage({
    super.key,
    required this.api,
    required this.employeeId,
    required this.workDate,
    required this.supervisorId,
  });

  @override
  State<PmReviewWorkerDetailPage> createState() => _PmReviewWorkerDetailPageState();
}

class _PmReviewWorkerDetailPageState extends State<PmReviewWorkerDetailPage> {
  bool loading = true;
  String? error;

  Map<String, dynamic>? workDay;
  List<Map<String, dynamic>> sessions = [];
  List<Map<String, dynamic>> scans = [];

  bool finalizing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      workDay = null;
      sessions = [];
      scans = [];
    });

    try {
      final json = await widget.api.getJson(
        '/api/v1/monitor/worker/${widget.employeeId}/day',
        query: {'work_date': widget.workDate},
      );

      Map<String, dynamic> data;
      if (json is Map && json['data'] is Map) {
        data = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json is Map) {
        data = Map<String, dynamic>.from(json as Map);
      } else {
        data = {};
      }

      setState(() {
        workDay = (data['work_day'] is Map) ? Map<String, dynamic>.from(data['work_day'] as Map) : null;
        sessions = _mapList(data['sessions']);
        scans = _mapList(data['scans']);
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<bool> _confirm(String title, String message, String okText) async {
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

  Future<void> _finalizeDay() async {
    if (finalizing) return;

    final ok = await _confirm(
      'Finalize Day',
      'Finalize the day for ${widget.employeeId} on ${widget.workDate}?\n\nThis will lock the day (CLOSED → FINALIZED).',
      'Finalize',
    );
    if (!ok) return;

    setState(() => finalizing = true);

    try {
      await widget.api.postJson(
        '/api/v1/supervisor/finalize-day',
        body: {
          'employee_id': widget.employeeId,
          'work_date': widget.workDate,
        },
      );

      _snack('Day finalized for ${widget.employeeId}');
      await _load();
    } catch (e) {
      _snack('Failed to finalize day: $e');
    } finally {
      if (mounted) setState(() => finalizing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (error != null) return Scaffold(appBar: AppBar(title: const Text('PM Review')), body: Center(child: Text('Error: $error')));

    final status = (workDay?['day_status'] ?? 'N/A').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('Review ${widget.employeeId} • ${widget.workDate}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('Status: $status', style: const TextStyle(fontWeight: FontWeight.bold))),
                  ElevatedButton(
                    onPressed: (status.toUpperCase() == 'CLOSED' && !finalizing) ? _finalizeDay : null,
                    child: finalizing
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Finalize Day'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text('Sessions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (sessions.isEmpty)
            const Text('No sessions.')
          else
            ...sessions.map((s) {
              return Card(
                child: ListTile(
                  title: Text('${s['project_id'] ?? '-'} • ${s['task_id'] ?? '-'}'),
                  subtitle: Text('Start: ${s['start_ts'] ?? '-'}\nEnd: ${s['end_ts'] ?? '-'}\nMinutes: ${s['duration_minutes'] ?? '-'}  Status: ${s['status'] ?? '-'}'),
                ),
              );
            }),

          const SizedBox(height: 12),
          Text('Scans / Tasks', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (scans.isEmpty)
            const Text('No scans.')
          else
            ...scans.map((sc) {
              return Card(
                child: ListTile(
                  title: Text('${sc['project_id'] ?? '-'} • ${sc['task_id'] ?? '-'}'),
                  subtitle: Text('Time: ${sc['scan_ts'] ?? sc['created_at'] ?? '-'}\nStatus: ${sc['scan_status'] ?? '-'}\nRef: ${sc['client_reference_id'] ?? '-'}'),
                ),
              );
            }),

          const SizedBox(height: 16),
          Card(
            color: Colors.grey.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Next (Phase 2.7): Return to Supervisor / Update Task / Re-close flow.\n'
                'This needs a dedicated endpoint + tracked reason/status (not DB schema change necessarily, but workflow fields).',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
