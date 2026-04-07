import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../app/app_state.dart';

class ActivityPage extends StatefulWidget {
  final ApiClient api;
  const ActivityPage({super.key, required this.api});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  String _lastWorkDate = '';
  String _search = '';
  String _statusFilter = 'ALL';

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
      items = [];
    });

    try {
      final res = await widget.api.getJson(
        '/monitor/activity',
        query: {'work_date': workDate},
      );

      final list = (res is Map ? (res['activities'] ?? []) : []) as List;

      setState(() {
        items = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String _safe(dynamic v) => (v ?? '').toString();

  String _time(String? ts) {
    if (ts == null || ts.isEmpty) return '-';
    try {
      final d = DateTime.parse(ts).toLocal();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      final ss = d.second.toString().padLeft(2, '0');
      return "$hh:$mm:$ss";
    } catch (_) {
      return ts;
    }
  }

  String _statusOf(Map<String, dynamic> m) =>
      _safe(m['scan_status']).isEmpty ? '-' : _safe(m['scan_status']);

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    final q = _search.trim().toLowerCase();

    return items.where((m) {
      final status = _statusOf(m).toUpperCase();

      if (_statusFilter != 'ALL' && status != _statusFilter) {
        return false;
      }

      if (q.isEmpty) return true;

      final haystack = [
        _safe(m['worker_name']),
        _safe(m['worker_id']),
        _safe(m['supervisor_name']),
        _safe(m['supervisor_id']),
        _safe(m['project_id']),
        _safe(m['task_id']),
        _safe(m['task_code']),
        _safe(m['task_name']),
        _safe(m['scan_status']),
      ].join(' ').toLowerCase();

      return haystack.contains(q);
    }).toList();
  }

  int get _acceptedCount =>
      items.where((m) => _statusOf(m).toUpperCase() == 'ACCEPTED').length;
  int get _rejectedCount =>
      items.where((m) => _statusOf(m).toUpperCase() == 'REJECTED').length;

  int get _workerCount {
    final set = <String>{};
    for (final m in items) {
      final id = _safe(m['worker_id']);
      if (id.isNotEmpty) set.add(id);
    }
    return set.length;
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.withOpacity(0.12),
              child: Icon(icon, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
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
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _openWorkerDrilldown(Map<String, dynamic> row) async {
    final workerId = _safe(row['worker_id']);
    final workDate = _lastWorkDate;

    if (workerId.isEmpty) {
      _showSimpleDialog(
        title: 'Activity Details',
        content: 'Worker ID is missing for this row.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkerDayDrilldownDialog(
        api: widget.api,
        workDate: workDate,
        activityRow: row,
      ),
    );
  }

  void _showSimpleDialog({
    required String title,
    required String content,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _activityTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 90, child: Text("Time", style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text("Worker", style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text("Supervisor", style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text("Project / Task", style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 110, child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final m = rows[i];

                final workerName = _safe(m['worker_name']);
                final workerId = _safe(m['worker_id']);
                final supervisorName = _safe(m['supervisor_name']);
                final supervisorId = _safe(m['supervisor_id']);
                final projectId = _safe(m['project_id']);
                final taskCode =
                    _safe(m['task_code']).isEmpty ? _safe(m['task_id']) : _safe(m['task_code']);
                final taskName = _safe(m['task_name']);
                final status = _statusOf(m);
                final time = _time(
                  _safe(m['scan_timestamp_server']).isEmpty
                      ? _safe(m['scan_timestamp_device'])
                      : _safe(m['scan_timestamp_server']),
                );

                return InkWell(
                  onTap: () => _openWorkerDrilldown(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(time),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            workerName.isEmpty ? workerId : "$workerName${workerId.isEmpty ? '' : ' ($workerId)'}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            supervisorName.isEmpty
                                ? supervisorId
                                : "$supervisorName${supervisorId.isEmpty ? '' : ' ($supervisorId)'}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "$projectId / $taskCode${taskName.isEmpty ? '' : ' — $taskName'}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _statusChip(status),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredItems;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Text(
          error!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _summaryCard(
                title: 'Total Activity',
                value: items.length.toString(),
                icon: Icons.list_alt,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                title: 'Workers',
                value: _workerCount.toString(),
                icon: Icons.people,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                title: 'Accepted',
                value: _acceptedCount.toString(),
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 12),
              _summaryCard(
                title: 'Rejected',
                value: _rejectedCount.toString(),
                icon: Icons.cancel_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search worker / supervisor / task / project',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All')),
                    DropdownMenuItem(value: 'ACCEPTED', child: Text('Accepted')),
                    DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _statusFilter = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _load(_lastWorkDate),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('No activity matches the current filters.'),
                  )
                : _activityTable(rows),
          ),
        ],
      ),
    );
  }
}

class _WorkerDayDrilldownDialog extends StatefulWidget {
  final ApiClient api;
  final String workDate;
  final Map<String, dynamic> activityRow;

  const _WorkerDayDrilldownDialog({
    required this.api,
    required this.workDate,
    required this.activityRow,
  });

  @override
  State<_WorkerDayDrilldownDialog> createState() => _WorkerDayDrilldownDialogState();
}

class _WorkerDayDrilldownDialogState extends State<_WorkerDayDrilldownDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  String _safe(dynamic v) => (v ?? '').toString();

  String _fmtTs(dynamic ts) {
    final s = _safe(ts);
    if (s.isEmpty) return '-';
    try {
      final d = DateTime.parse(s).toLocal();
      return "${d.year.toString().padLeft(4, '0')}-"
          "${d.month.toString().padLeft(2, '0')}-"
          "${d.day.toString().padLeft(2, '0')} "
          "${d.hour.toString().padLeft(2, '0')}:"
          "${d.minute.toString().padLeft(2, '0')}:"
          "${d.second.toString().padLeft(2, '0')}";
    } catch (_) {
      return s;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workerId = _safe(widget.activityRow['worker_id']);

    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });

    try {
      final res = await widget.api.getJson(
        '/monitor/worker/$workerId/day',
        query: {'work_date': widget.workDate},
      );

      setState(() {
        _data = (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.activityRow;
    final workerName = _safe(row['worker_name']);
    final workerId = _safe(row['worker_id']);
    final supervisorName = _safe(row['supervisor_name']);
    final supervisorId = _safe(row['supervisor_id']);
    final projectId = _safe(row['project_id']);
    final taskCode = _safe(row['task_code']).isEmpty ? _safe(row['task_id']) : _safe(row['task_code']);
    final taskName = _safe(row['task_name']);
    final status = _safe(row['scan_status']);

    final summary = (_data != null && _data!['summary'] is Map)
        ? Map<String, dynamic>.from(_data!['summary'])
        : <String, dynamic>{};

    final sessions = (_data != null && _data!['sessions'] is List)
        ? List<Map<String, dynamic>>.from(
            (_data!['sessions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final scans = (_data != null && _data!['scans'] is List)
        ? List<Map<String, dynamic>>.from(
            (_data!['scans'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        height: 700,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null)
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Worker Day Drilldown • $workerName${workerId.isEmpty ? '' : ' ($workerId)'}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                        Text('Work Date: ${widget.workDate}'),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _InfoBox(
                              title: 'Supervisor',
                              value: supervisorName.isEmpty
                                  ? (supervisorId.isEmpty ? '-' : supervisorId)
                                  : '$supervisorName${supervisorId.isEmpty ? '' : ' ($supervisorId)'}',
                            ),
                            _InfoBox(
                              title: 'Project',
                              value: projectId.isEmpty ? '-' : projectId,
                            ),
                            _InfoBox(
                              title: 'Task',
                              value: taskCode.isEmpty
                                  ? '-'
                                  : '$taskCode${taskName.isEmpty ? '' : ' — $taskName'}',
                            ),
                            _InfoBox(
                              title: 'Selected Row Status',
                              value: status.isEmpty ? '-' : status,
                            ),
                            _InfoBox(
                              title: 'Accepted Scans',
                              value: _safe(summary['accepted_scans']).isEmpty
                                  ? '0'
                                  : _safe(summary['accepted_scans']),
                            ),
                            _InfoBox(
                              title: 'Rejected Scans',
                              value: _safe(summary['rejected_scans']).isEmpty
                                  ? '0'
                                  : _safe(summary['rejected_scans']),
                            ),
                            _InfoBox(
                              title: 'Total Minutes',
                              value: _safe(summary['total_minutes']).isEmpty
                                  ? '0'
                                  : _safe(summary['total_minutes']),
                            ),
                          ],
                        ),

                        _sectionTitle('Task Sessions'),
                        Expanded(
                          child: sessions.isEmpty
                              ? const Center(child: Text('No sessions found for this worker/day.'))
                              : Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListView.separated(
                                    itemCount: sessions.length,
                                    separatorBuilder: (_, __) =>
                                        Divider(height: 1, color: Colors.grey.shade200),
                                    itemBuilder: (_, i) {
                                      final s = sessions[i];
                                      return ListTile(
                                        title: Text(
                                          "${_safe(s['project_id'])} / ${_safe(s['task_id'])}",
                                        ),
                                        subtitle: Text(
                                          "Start: ${_fmtTs(s['start_ts'])}   •   "
                                          "End: ${_fmtTs(s['end_ts'])}   •   "
                                          "Minutes: ${_safe(s['duration_minutes']).isEmpty ? '0' : _safe(s['duration_minutes'])}",
                                        ),
                                        trailing: Text(
                                          _safe(s['status']).isEmpty ? '-' : _safe(s['status']),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),

                        _sectionTitle('Scans'),
                        Expanded(
                          child: scans.isEmpty
                              ? const Center(child: Text('No scans found for this worker/day.'))
                              : Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListView.separated(
                                    itemCount: scans.length,
                                    separatorBuilder: (_, __) =>
                                        Divider(height: 1, color: Colors.grey.shade200),
                                    itemBuilder: (_, i) {
                                      final s = scans[i];
                                      return ListTile(
                                        title: Text(
                                          "${_safe(s['project_id'])} / ${_safe(s['task_id'])}",
                                        ),
                                        subtitle: Text(
                                          "Device Time: ${_fmtTs(s['scan_timestamp_device'])}   •   "
                                          "Server Time: ${_fmtTs(s['scan_timestamp_server'])}",
                                        ),
                                        trailing: Text(
                                          _safe(s['scan_status']).isEmpty ? '-' : _safe(s['scan_status']),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: _safe(s['scan_status']).toUpperCase() == 'ACCEPTED'
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),

                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String value;

  const _InfoBox({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}