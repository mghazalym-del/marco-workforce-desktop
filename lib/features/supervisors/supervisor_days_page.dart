import 'dart:async';
import 'package:flutter/material.dart';
import 'supervisor_day_workers_page.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class SupervisorDaysPage extends StatefulWidget {
  final ApiClient api;
  const SupervisorDaysPage({super.key, required this.api});

  @override
  State<SupervisorDaysPage> createState() => _SupervisorDaysPageState();
}

class _SupervisorDaysPageState extends State<SupervisorDaysPage> {
  String? selectedSupervisorId;

  bool _supervisorsLoading = false;
  String? _supervisorsError;
  List<Map<String, dynamic>> _supervisors = [];

  bool _daysLoading = false;
  String? _daysError;
  List<Map<String, dynamic>> _days = [];

  bool _controlWorkersLoading = false;
  String? _controlWorkersError;
  List<Map<String, dynamic>> _controlWorkers = [];

  String? _lastSelectedDateStr;

  final TextEditingController _daysFromDateCtrl = TextEditingController();
  final TextEditingController _daysToDateCtrl = TextEditingController();

  final Map<String, Future<_Rollup>> _rollupFutureByDate = {};

  List<Map<String, dynamic>> _extractList(dynamic json, {String? dataKey}) {
    dynamic v = json;
    if (v is Map<String, dynamic> && v.containsKey('data')) v = v['data'];

    if (v is List) {
      return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }

    if (v is Map) {
      final m = v.cast<String, dynamic>();
      if (dataKey != null && m[dataKey] is List) {
        return (m[dataKey] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      // fallback: first list value in the map
      for (final entry in m.entries) {
        if (entry.value is List) {
          return (entry.value as List)
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList();
        }
      }
    }
    return <Map<String, dynamic>>[];
  }

  @override
  void dispose() {
    _daysFromDateCtrl.dispose();
    _daysToDateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final st = context.watch<AppState>();
    final selected = st.selectedDateStr;

    // Keep the date range in sync with the top date picker (AppState.selectedDate).
    // If user changes the selected date, update To/From and refresh rows.
    if (_lastSelectedDateStr != selected) {
      _lastSelectedDateStr = selected;

      _daysToDateCtrl.text = selected;

      final dt = _dateParse(selected) ?? DateTime.now();
      _daysFromDateCtrl.text = _dateFmt(dt.subtract(const Duration(days: 6)));

      // Clear cached rollups so the UI doesn't show stale zeros.
      _rollupFutureByDate.clear();

      if (selectedSupervisorId != null) {
        unawaited(_loadDays());
        unawaited(_loadControlWorkers());
      }
    }

    // First load (initial mount)
    if (_daysToDateCtrl.text.isEmpty) _daysToDateCtrl.text = selected;
    if (_daysFromDateCtrl.text.isEmpty) {
      final dt = _dateParse(selected) ?? DateTime.now();
      _daysFromDateCtrl.text = _dateFmt(dt.subtract(const Duration(days: 6)));
    }

    // first load
    if (_supervisors.isEmpty && !_supervisorsLoading && _supervisorsError == null) {
      unawaited(_loadSupervisors());
    }
  }

  DateTime? _dateParse(String yyyyMmDd) {
    try {
      final p = yyyyMmDd.split('-');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  String _dateFmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  Future<void> _loadSupervisors() async {
    setState(() {
      _supervisorsLoading = true;
      _supervisorsError = null;
    });

    try {
      // ✅ Correct endpoint + correct response shape: data.supervisors
      final app = context.read<AppState>();
      final role = app.role.toUpperCase();

      final endpoint = (role == 'SE' || role == 'PM')
          ? '/api/v1/se/supervisors'
          : '/api/v1/monitor/supervisors'; // ADMIN stays here

      final json = await widget.api.getJson(endpoint);
      final supervisors = _extractList(json, dataKey: 'supervisors');

      setState(() {
        _supervisors = supervisors;
        if (selectedSupervisorId == null && _supervisors.isNotEmpty) {
          selectedSupervisorId = (_supervisors.first['employee_id'] ?? '').toString();
        }
      });

      await _loadDays();
      await _loadControlWorkers();
    } catch (e) {
      setState(() {
        _supervisorsError = e.toString();
        _supervisors = [];
        selectedSupervisorId = null;
      });
    } finally {
      setState(() => _supervisorsLoading = false);
    }
  }

  Future<void> _loadDays() async {
    if (selectedSupervisorId == null) return;

    setState(() {
      _daysLoading = true;
      _daysError = null;
    });

    try {
      // ✅ Do NOT depend on backend "days" endpoint (it changed a lot).
      // Generate the day rows locally and use _getRollup(work_date) for live values.
      final to = _dateParse(_daysToDateCtrl.text) ?? DateTime.now();
      final from = _dateParse(_daysFromDateCtrl.text) ?? to.subtract(const Duration(days: 6));

      final start = from.isBefore(to) ? from : to;
      final end = from.isBefore(to) ? to : from;

      final days = <Map<String, dynamic>>[];
      for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        days.add({'work_date': _dateFmt(d)});
      }

      setState(() {
        _days = days.reversed.toList(); // newest first
      });
    } catch (e) {
      setState(() {
        _daysError = e.toString();
        _days = [];
      });
    } finally {
      setState(() => _daysLoading = false);
    }
  }

  Future<void> _loadControlWorkers() async {
    if (selectedSupervisorId == null) return;

    final st = context.read<AppState>();
    final workDate = st.selectedDateStr;

    setState(() {
      _controlWorkersLoading = true;
      _controlWorkersError = null;
      _controlWorkers = [];
    });

    try {
      // Fetch workers that belong to this supervisor for the selected date
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/$selectedSupervisorId/workers',
        query: {'work_date': workDate},
      );

      final workers = _extractList(json, dataKey: 'workers');

      // Enrich with per-worker day summary (sessions/minutes/open_task)
      final summaries = await Future.wait(workers.map((w) async {
        final empId = (w['employee_id'] ?? w['worker_id'] ?? '').toString();
        if (empId.isEmpty) return <String, dynamic>{'employee_id': ''};

        try {
          final sum = await widget.api.getJson(
            '/api/v1/assignments/day/summary/$empId',
            query: {'work_date': workDate},
          );

          final s = (sum is Map<String, dynamic>) ? sum : <String, dynamic>{};
          return <String, dynamic>{
            'employee_id': empId,
            'sessions_count': (s['sessions_count'] ?? 0),
            'total_minutes': (s['total_minutes'] ?? 0),
            'total_hours': (s['total_hours'] ?? 0),
            'open_task': s['open_task'],
          };
        } catch (_) {
          // If summary fails for one worker, keep worker row but leave counts 0
          return <String, dynamic>{
            'employee_id': empId,
            'sessions_count': 0,
            'total_minutes': 0,
            'total_hours': 0,
            'open_task': null,
          };
        }
      }));

      final byEmp = <String, Map<String, dynamic>>{
        for (final s in summaries)
          if ((s['employee_id'] ?? '').toString().isNotEmpty)
            (s['employee_id'] as String): s,
      };

      final enriched = workers.map((w) {
        final empId = (w['employee_id'] ?? w['worker_id'] ?? '').toString();
        final s = byEmp[empId];
        return <String, dynamic>{
          ...w,
          if (s != null) ...s,
        };
      }).toList();

      setState(() {
        _controlWorkers = enriched;
      });
    } catch (e) {
      setState(() {
        _controlWorkersError = e.toString();
        _controlWorkers = [];
      });
    } finally {
      setState(() => _controlWorkersLoading = false);
    }
  }

  Future<_Rollup> _getRollup(String workDate) {
    final key = "${selectedSupervisorId ?? ''}|$workDate";
    return _rollupFutureByDate.putIfAbsent(key, () async {
      // For the day rows we want: sessions/minutes/open_tasks.
      // The monitor workers endpoint does NOT include these rollups reliably,
      // so we compute them from /assignments/day/summary per worker (backend confirmed OK).
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/$selectedSupervisorId/workers',
        query: {'work_date': workDate},
      );

      final workers = _extractList(json, dataKey: 'workers');

      int sessions = 0;
      int minutes = 0;
      int openTasks = 0;

      // Parallel fetch summaries (small fan-out typical for a supervisor)
      final sums = await Future.wait(workers.map((w) async {
        final empId = (w['employee_id'] ?? w['worker_id'] ?? '').toString();
        if (empId.isEmpty) return <String, dynamic>{};

        try {
          final s = await widget.api.getJson(
            '/api/v1/assignments/day/summary/$empId',
            query: {'work_date': workDate},
          );

          if (s is! Map<String, dynamic>) return <String, dynamic>{};

          // Backend response is wrapped inside { success, data }
          final data = s['data'] as Map<String, dynamic>?;

          if (data == null) return <String, dynamic>{};

          return {
            'sessions_count': data['sessions_count'],
            'total_minutes': data['total_minutes'],
            'open_task': data['open_task'],
          };
        } catch (_) {
          return <String, dynamic>{};
        }
      }));

      for (final d in sums) {
        final sc = d['sessions_count'];
        final tm = d['total_minutes'];

        sessions += (sc is int) ? sc : int.tryParse('$sc') ?? 0;
        minutes += (tm is int) ? tm : int.tryParse('$tm') ?? 0;

        if (d['open_task'] != null) openTasks++;
      }

//////////// till here
      return _Rollup(
        sessionsCount: sessions,
        totalMinutes: minutes,
        openTasksCount: openTasks,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();

    return Column(
      children: [
        // --- Top Supervisor selector (keep existing design intent) ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text("Supervisor:", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: _supervisorsLoading
                    ? const LinearProgressIndicator(minHeight: 2)
                    : DropdownButton<String>(
                        isExpanded: true,
                        value: selectedSupervisorId,
                        hint: const Text("Select a supervisor"),
                        items: _supervisors.map((s) {
                          final id = (s['employee_id'] ?? '').toString();
                          final name = (s['full_name'] ?? s['employee_name'] ?? '').toString();
                          return DropdownMenuItem(
                            value: id,
                            child: Text("$id — $name"),
                          );
                        }).toList(),
                        onChanged: (v) async {
                          setState(() {
                            selectedSupervisorId = v;
                            _days = [];
                            _controlWorkers = [];
                          });
                          await _loadDays();
                          await _loadControlWorkers();
                        },
                      ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: "Refresh",
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await _loadSupervisors();
                },
              ),
            ],
          ),
        ),

        if (_supervisorsError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text("Error: $_supervisorsError"),
          ),

        // Your original page has Tabs ("Days" / "Day Control").
        // Keep your existing Tab UI below; we only fixed data sources.
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: "Days"),
                    Tab(text: "Day Control"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // DAYS TAB
                      _buildDaysTab(st),
                      // DAY CONTROL TAB
                      _buildDayControlTab(st),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaysTab(AppState st) {
    if (selectedSupervisorId == null) return const Center(child: Text("Select a supervisor."));
    if (_daysLoading) return const Center(child: CircularProgressIndicator());
    if (_daysError != null) return Center(child: Text("Error: $_daysError"));
    if (_days.isEmpty) return const Center(child: Text("No days found"));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final workDate = (_days[i]['work_date'] ?? '').toString();

        return FutureBuilder<_Rollup?>(
          future: _getRollup(workDate),
          builder: (context, snap) {
            final r = snap.data;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      workDate,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),

                  // ✅ show spinner only while waiting
                  if (snap.connectionState == ConnectionState.waiting)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),

                  // ✅ if error, stop spinning and show error indicator
                  if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'Failed',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                      ),
                    ),

                  // ✅ show values when ready
                  if (!snap.hasError && r != null) ...[
                    Text("Sessions: ${r.sessionsCount}  "),
                    Text("Minutes: ${r.totalMinutes}  "),
                    Text("Open tasks: ${r.openTasksCount}"),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayControlTab(AppState st) {
    if (selectedSupervisorId == null) return const Center(child: Text("Select a supervisor."));
    // Reuse the dedicated Day Workers page inside the tab so we keep behavior consistent
    return SupervisorDayWorkersPage(
      api: widget.api,
      supervisorId: selectedSupervisorId!,
      workDate: st.selectedDateStr,
    );
  }
}

class _Rollup {
  final int sessionsCount;
  final int totalMinutes;
  final int openTasksCount;
  _Rollup({
    required this.sessionsCount,
    required this.totalMinutes,
    required this.openTasksCount,
  });
}
