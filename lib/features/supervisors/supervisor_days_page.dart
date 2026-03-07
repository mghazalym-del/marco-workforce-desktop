import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';
import 'supervisor_day_workers_page.dart';

class SupervisorDaysPage extends StatefulWidget {
  final ApiClient api;
  const SupervisorDaysPage({super.key, required this.api});

  @override
  State<SupervisorDaysPage> createState() => _SupervisorDaysPageState();
}

Map<String, String>? _qs(Map<String, dynamic>? q) {
  if (q == null) return null;
  return q.map((k, v) => MapEntry(k, v.toString()));
}

class _SupervisorDaysPageState extends State<SupervisorDaysPage> {
  String _dateOnly(String s) {
    if (s.isEmpty) return s;
    return (s.length >= 10) ? s.substring(0, 10) : s;
  }


  bool _supervisorsLoading = false;
  String? _supervisorsError;
  List<Map<String, dynamic>> _supervisors = [];
  String? selectedSupervisorId;

  bool _daysLoading = false;
  String? _daysError;
  List<Map<String, dynamic>> _days = [];

  bool _controlLoading = false;
  String? _controlError;
  List<Map<String, dynamic>> _controlWorkers = [];

  // cache rollups per supervisorId|date
  final Map<String, Future<_Rollup>> _rollupFutureByDate = {};

  String _lastWorkDate = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    final workDate = app.selectedDateStr;
    if (_lastWorkDate != workDate) {
      _lastWorkDate = workDate;
      // When date changes: clear caches and reload.
      _rollupFutureByDate.clear();
      _loadDays();
      _loadControlWorkers();
    }
  }

  // ---------- helpers ----------
  List<Map<String, dynamic>> _extractList(dynamic json, {required String dataKey}) {
    try {
      if (json is Map && json['data'] is Map) {
        final data = json['data'] as Map;
        final list = data[dataKey];
        if (list is List) {
          return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      if (json is Map) {
        final list = json[dataKey];
        if (list is List) {
          return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  String _roleUpper(AppState app) => (app.role).toUpperCase();

  Future<dynamic> _getJsonWithFallback({
    required String primary,
    required List<String> fallbacks,
    Map<String, dynamic>? query,
  }) async {
    try {
      return await widget.api.getJson(primary, query: _qs(query));
    } catch (_) {
      for (final p in fallbacks) {
        try {
          return await widget.api.getJson(p, query: _qs(query));
        } catch (_) {}
      }
      rethrow;
    }
  }

  // ---------- loading ----------
  Future<void> _loadSupervisors() async {
    setState(() {
      _supervisorsLoading = true;
      _supervisorsError = null;
    });

    final app = context.read<AppState>();
    final role = _roleUpper(app);

    // Role-aware source:
    // - SE/PM should prefer /api/v1/se/supervisors (scoped)
    // - fallback to /api/v1/monitor/supervisors (works today in your setup)
    final primary = (role == 'SE' || role == 'PM') ? '/api/v1/se/supervisors' : '/api/v1/monitor/supervisors';
    final fallbacks = <String>[
      // keep monitor as fallback always
      '/api/v1/monitor/supervisors',
      // if some builds still rely on admin route for supervisors
      '/api/v1/admin/supervisors',
    ];

    try {
      final json = await _getJsonWithFallback(primary: primary, fallbacks: fallbacks);

      final supervisors = _extractList(json, dataKey: 'supervisors');

      setState(() {
        _supervisors = supervisors;

        // keep selectedSupervisorId stable if still exists
        if (_supervisors.isEmpty) {
          selectedSupervisorId = null;
        } else {
          final current = selectedSupervisorId;
          if (current == null || !_supervisors.any((s) => (s['employee_id'] ?? '').toString() == current)) {
            selectedSupervisorId = (_supervisors.first['employee_id'] ?? '').toString();
          }
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
    final app = context.read<AppState>();
    final supId = selectedSupervisorId;
    if (supId == null || supId.isEmpty) {
      setState(() {
        _days = [];
        _daysError = null;
        _daysLoading = false;
      });
      return;
    }

    setState(() {
      _daysLoading = true;
      _daysError = null;
      _days = [];
    });

    try {
      // Date range used by your UI (last 7 days, including selected date)
      final end = app.selectedDate;
      final start = end.subtract(const Duration(days: 7));

      String fmt(DateTime d) => d.toIso8601String().substring(0, 10);

      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/$supId/days',
        query: {'from': fmt(start), 'to': fmt(end)},
      );

      final days = _extractList(json, dataKey: 'days');

      setState(() {
        _days = days;
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
    final app = context.read<AppState>();
    final supId = selectedSupervisorId;
    if (supId == null || supId.isEmpty) {
      setState(() {
        _controlWorkers = [];
        _controlError = null;
        _controlLoading = false;
      });
      return;
    }

    setState(() {
      _controlLoading = true;
      _controlError = null;
      _controlWorkers = [];
    });

    try {
      // Use the same day-control page to compute summaries per worker
      // We pre-load the base worker list (name + status) so the Day Control tab loads quickly.
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/$supId/workers',
        query: {'work_date': app.selectedDateStr},
      );

      final workers = _extractList(json, dataKey: 'workers');

      setState(() {
        _controlWorkers = workers;
      });
    } catch (e) {
      setState(() {
        _controlError = e.toString();
        _controlWorkers = [];
      });
    } finally {
      setState(() => _controlLoading = false);
    }
  }

  // ---------- rollups (day rows) ----------
  Future<_Rollup> _getRollup(String workDate) {
    final key = "${selectedSupervisorId ?? ''}|$workDate";
    return _rollupFutureByDate.putIfAbsent(key, () async {
      final supId = selectedSupervisorId;
      if (supId == null || supId.isEmpty) return _Rollup.zero();

      // Base worker list for that date
      final json = await widget.api.getJson(
        '/api/v1/monitor/supervisors/$supId/workers',
        query: {'work_date': workDate},
      );
      final workers = _extractList(json, dataKey: 'workers');

      int sessions = 0;
      int minutes = 0;
      int openTasks = 0;

      final sums = await Future.wait(workers.map((w) async {
        final empId = (w['employee_id'] ?? w['worker_id'] ?? '').toString();
        if (empId.isEmpty) return <String, dynamic>{};

        try {
          final sum = await widget.api.getJson(
            '/api/v1/assignments/day/summary/$empId',
            query: {'work_date': workDate},
          );

          if (sum is Map && sum['data'] is Map) return Map<String, dynamic>.from(sum['data'] as Map);
          if (sum is Map) return Map<String, dynamic>.from(sum);
        } catch (_) {}
        return <String, dynamic>{};
      }));

      for (final s in sums) {
        final sc = s['sessions_count'];
        final tm = s['total_minutes'];
        sessions += (sc is int) ? sc : int.tryParse('$sc') ?? 0;
        minutes += (tm is int) ? tm : int.tryParse('$tm') ?? 0;
        if (s['open_task'] != null) openTasks++;
      }

      return _Rollup(sessionsCount: sessions, totalMinutes: minutes, openTasksCount: openTasks);
    });
  }

  @override
  void initState() {
    super.initState();
    // load supervisors once when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSupervisors());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Supervisors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadSupervisors,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Supervisor dropdown
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
                  items: _supervisors.map((s) {
                    final id = (s['employee_id'] ?? '').toString();
                    final name = (s['full_name'] ?? '').toString();
                    return DropdownMenuItem(value: id, child: Text('$id — $name'));
                  }).toList(),
                  onChanged: (v) async {
                    setState(() {
                      selectedSupervisorId = v;
                      _rollupFutureByDate.clear();
                    });
                    await _loadDays();
                    await _loadControlWorkers();
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (_supervisorsLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),

          if (_supervisorsError != null) ...[
            const SizedBox(height: 10),
            Text('Error: $_supervisorsError', style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 16),

          // Tabs: Days + Day Control
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Days'),
                      Tab(text: 'Day Control'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildDaysTab(app),
                        _buildControlTab(app),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysTab(AppState app) {
    if (_daysLoading) return const Center(child: CircularProgressIndicator());
    if (_daysError != null) return Center(child: Text('Error: $_daysError'));
    if (_days.isEmpty) return const Center(child: Text('No days in range.'));

    return ListView.separated(
      itemCount: _days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final day = _days[i];
        final workDateRaw = (day['work_date'] ?? day['date'] ?? '').toString();
        final workDate = _dateOnly(workDateRaw);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workDate, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FutureBuilder<_Rollup>(
                  future: _getRollup(workDate),
                  builder: (context, snap) {
                    final r = snap.data;
                    return Row(
                      children: [
                        if (r == null) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        if (r != null) ...[
                          Text("Sessions: ${r.sessionsCount}  "),
                          Text("Minutes: ${r.totalMinutes}  "),
                          Text("Open tasks: ${r.openTasksCount}"),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlTab(AppState app) {
    final supId = selectedSupervisorId;
    if (supId == null || supId.isEmpty) {
      return const Center(child: Text('Select a supervisor.'));
    }

    if (_controlLoading) return const Center(child: CircularProgressIndicator());
    if (_controlError != null) return Center(child: Text('Error: $_controlError'));

    // Delegate actual control logic to the workers page (it fetches + summary + actions)
    return SupervisorDayWorkersPage(
      api: widget.api,
      supervisorId: supId,
      workDate: app.selectedDateStr,
      onDataChanged: () async {
        // When actions happen (close/finalize/return), refresh both tabs.
        _rollupFutureByDate.clear();
        await _loadDays();
        await _loadControlWorkers();
      },
    );
  }
}

class _Rollup {
  final int sessionsCount;
  final int totalMinutes;
  final int openTasksCount;

  const _Rollup({
    required this.sessionsCount,
    required this.totalMinutes,
    required this.openTasksCount,
  });

  factory _Rollup.zero() => const _Rollup(sessionsCount: 0, totalMinutes: 0, openTasksCount: 0);
}