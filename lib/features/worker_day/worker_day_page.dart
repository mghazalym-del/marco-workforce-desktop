import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class WorkerDayPage extends StatefulWidget {
  const WorkerDayPage({
    super.key,
    required this.api,
    required this.employeeId,
    required this.fullName,
    required this.workDate, // kept for compatibility; date is controlled internally
  });

  final ApiClient api;
  final String employeeId;
  final String fullName;
  final String workDate;

  @override
  State<WorkerDayPage> createState() => _WorkerDayPageState();
}

class _WorkerDayPageState extends State<WorkerDayPage> {
  bool loading = true;
  String? error;

  Map<String, dynamic>? workDay;
  List<Map<String, dynamic>> scans = [];
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic>? summary;

  // Date selector (last 3 days)
  DateTime _selectedDate = DateTime.now();

  // Filters
  String _scanStatusFilter = 'All';
  String _scanSupervisorFilter = 'All';

  String _sessionProjectFilter = 'All';
  String _sessionTaskFilter = 'All';

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    _load();
  }

  String get _selectedDateStr {
    // Display + send as YYYY-MM-DD; backend expects date string.
    final d = _selectedDate;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  void _setDate(DateTime d) {
    setState(() {
      _selectedDate = DateTime(d.year, d.month, d.day);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final json = await widget.api.getJson(
        // Let ApiClient add /api/v1
        '/monitor/worker/${widget.employeeId}/day',
        query: {'work_date': _selectedDateStr},
      );

      // ✅ Accept both shapes:
      // 1) { work_day, scans, sessions, summary }  (already unwrapped)
      // 2) { data: { work_day, scans, sessions, summary } } (old behavior)
      Map<String, dynamic> data;
      if (json is Map && json['data'] is Map) {
        data = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json is Map) {
        data = Map<String, dynamic>.from(json as Map);
      } else {
        data = <String, dynamic>{};
      }

      workDay = (data['work_day'] is Map)
          ? Map<String, dynamic>.from(data['work_day'] as Map)
          : null;

      final rawScans = (data['scans'] as List?) ?? const [];
      scans = rawScans
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final rawSessions = (data['sessions'] as List?) ?? const [];
      sessions = rawSessions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      summary = (data['summary'] is Map)
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : null;

      _normalizeFilters();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }


  void _normalizeFilters() {
    final statusOptions = _scanStatusOptions();
    if (!statusOptions.contains(_scanStatusFilter)) _scanStatusFilter = 'All';

    final supOptions = _scanSupervisorOptions();
    if (!supOptions.contains(_scanSupervisorFilter)) _scanSupervisorFilter = 'All';

    final projOptions = _sessionProjectOptions();
    if (!projOptions.contains(_sessionProjectFilter)) _sessionProjectFilter = 'All';

    final taskOptions = _sessionTaskOptions(projectFilter: _sessionProjectFilter);
    if (!taskOptions.contains(_sessionTaskFilter)) _sessionTaskFilter = 'All';
  }

  // ---------- UI helpers ----------
  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withOpacity(0.06),
      ),
      child: Text(text),
    );
  }

  String _shortTs(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    // Try to show "YYYY-MM-DD HH:MM:SS" if present
    if (s.contains('T')) {
      // ISO: 2026-01-03T09:28:56.000Z
      final parts = s.split('T');
      if (parts.length >= 2) {
        final time = parts[1].replaceAll('Z', '');
        final hhmmss = time.split('.').first;
        return '${parts[0]} $hhmmss';
      }
    }
    // Postgres style: 2026-01-03 11:24:44.047
    if (s.length >= 19) return s.substring(0, 19);
    return s;
  }

  // ---------- filter options ----------
  List<String> _scanStatusOptions() {
    final set = <String>{};
    for (final s in scans) {
      final st = (s['scan_status'] ?? '').toString().trim();
      if (st.isNotEmpty) set.add(st);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<String> _scanSupervisorOptions() {
    final set = <String>{};
    for (final s in scans) {
      final sup = (s['supervisor_employee_id'] ?? '').toString().trim();
      if (sup.isNotEmpty) set.add(sup);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<String> _sessionProjectOptions() {
    final set = <String>{};
    for (final s in sessions) {
      final p = (s['project_id'] ?? '').toString().trim();
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<String> _sessionTaskOptions({required String projectFilter}) {
    final set = <String>{};
    for (final s in sessions) {
      final p = (s['project_id'] ?? '').toString().trim();
      if (projectFilter != 'All' && p != projectFilter) continue;
      final t = (s['task_id'] ?? '').toString().trim();
      if (t.isNotEmpty) set.add(t);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  // ---------- filtered data ----------
  List<Map<String, dynamic>> get _filteredScans {
    return scans.where((s) {
      final st = (s['scan_status'] ?? '').toString();
      final sup = (s['supervisor_employee_id'] ?? '').toString();
      if (_scanStatusFilter != 'All' && st != _scanStatusFilter) return false;
      if (_scanSupervisorFilter != 'All' && sup != _scanSupervisorFilter) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredSessions {
    return sessions.where((s) {
      final p = (s['project_id'] ?? '').toString();
      final t = (s['task_id'] ?? '').toString();
      if (_sessionProjectFilter != 'All' && p != _sessionProjectFilter) return false;
      if (_sessionTaskFilter != 'All' && t != _sessionTaskFilter) return false;
      return true;
    }).toList();
  }

  // ---------- widgets ----------
  Widget _dateSelectorRow() {
    return Row(
      children: [
        ElevatedButton(
          onPressed: () => _setDate(DateTime.now()),
          child: const Text('Today'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => _setDate(DateTime.now().subtract(const Duration(days: 1))),
          child: const Text('Yesterday'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => _setDate(DateTime.now().subtract(const Duration(days: 2))),
          child: const Text('Last 3 Days'),
        ),
        const Spacer(),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today),
          label: Text(_selectedDateStr),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime.now().subtract(const Duration(days: 3)),
              lastDate: DateTime.now(),
            );
            if (picked != null) _setDate(picked);
          },
        ),
      ],
    );
  }

  Widget _scansTableCard() {
    final rows = _filteredScans;

    final statusOptions = _scanStatusOptions();
    final supOptions = _scanSupervisorOptions();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Scans (${rows.length}/${scans.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                DropdownButton<String>(
                  value: _scanStatusFilter,
                  items: statusOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text('Status: $v')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _scanStatusFilter = v);
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _scanSupervisorFilter,
                  items: supOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text('Sup: $v')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _scanSupervisorFilter = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No scans for this filter/date.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('Project')),
                            DataColumn(label: Text('Task')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Supervisor')),
                            DataColumn(label: Text('Offline')),
                          ],
                          rows: rows.map((s) {
                            return DataRow(
                              cells: [
                                DataCell(Text(_shortTs(s['scan_timestamp_server']))),
                                DataCell(Text((s['project_id'] ?? '').toString())),
                                DataCell(Text((s['task_id'] ?? '').toString())),
                                DataCell(Text((s['scan_status'] ?? '').toString())),
                                DataCell(Text((s['supervisor_employee_id'] ?? '').toString())),
                                DataCell(Text((s['is_offline'] ?? false).toString())),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionsTableCard() {
    final rows = _filteredSessions;

    final projOptions = _sessionProjectOptions();
    final taskOptions = _sessionTaskOptions(projectFilter: _sessionProjectFilter);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Sessions (${rows.length}/${sessions.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                DropdownButton<String>(
                  value: _sessionProjectFilter,
                  items: projOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text('Project: $v')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _sessionProjectFilter = v;
                      // reset task filter if it no longer matches
                      final validTasks = _sessionTaskOptions(projectFilter: _sessionProjectFilter);
                      if (!validTasks.contains(_sessionTaskFilter)) _sessionTaskFilter = 'All';
                    });
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _sessionTaskFilter,
                  items: taskOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text('Task: $v')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _sessionTaskFilter = v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No sessions for this filter/date.'))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Start')),
                            DataColumn(label: Text('End')),
                            DataColumn(label: Text('Project')),
                            DataColumn(label: Text('Task')),
                            DataColumn(label: Text('Minutes')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Offline')),
                          ],
                          rows: rows.map((s) {
                            return DataRow(
                              cells: [
                                DataCell(Text(_shortTs(s['start_ts']))),
                                DataCell(Text(_shortTs(s['end_ts']))),
                                DataCell(Text((s['project_id'] ?? '').toString())),
                                DataCell(Text((s['task_id'] ?? '').toString())),
                                DataCell(Text((s['duration_minutes'] ?? 0).toString())),
                                DataCell(Text((s['status'] ?? '').toString())),
                                DataCell(Text((s['is_offline'] ?? false).toString())),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayStatus = (workDay?['day_status'] ?? 'N/A').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employeeId} — ${widget.fullName}'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dateSelectorRow(),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill('Date: $_selectedDateStr'),
                          _pill('Day: $dayStatus'),
                          _pill('Accepted: ${summary?['accepted_scans'] ?? 0}'),
                          _pill('Rejected: ${summary?['rejected_scans'] ?? 0}'),
                          _pill('Minutes: ${summary?['total_minutes'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _scansTableCard()),
                            const SizedBox(width: 12),
                            Expanded(child: _sessionsTableCard()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
