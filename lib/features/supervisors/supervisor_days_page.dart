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

  final Map<String, Future<_Rollup>> _rollupFutureByDate = {};

  String _lastWorkDate = '';

  @override
  void initState() {
    super.initState();
    _loadSupervisors();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    final workDate = app.selectedDateStr;
    if (_lastWorkDate != workDate) {
      _lastWorkDate = workDate;
      _rollupFutureByDate.clear();
      _loadDays();
      _loadControlWorkers();
    }
  }

  List<Map<String, dynamic>> _extractList(dynamic json, {required String dataKey}) {
    try {
      if (json is Map && json[dataKey] is List) {
        return (json[dataKey] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

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

  Future<void> _loadSupervisors() async {
    setState(() {
      _supervisorsLoading = true;
      _supervisorsError = null;
    });

    final app = context.read<AppState>();
    final role = _roleUpper(app);
    final myId = app.profile?.employeeId ?? '';

    try {
      List<Map<String, dynamic>> supervisors = [];

      if (role == 'SE') {
        final json = await widget.api.getJson('/se/supervisors');
        supervisors = _extractList(json, dataKey: 'supervisors');
      } else if (role == 'ADMIN' || role == 'SUPERVISOR') {
        // Supervisor/admin sees only own record
        supervisors = [
          {
            'employee_id': myId,
            'full_name': app.profile?.fullName ?? myId,
            'role': role,
          }
        ];
      } else {
        // PM and others can use broader list
        final json = await _getJsonWithFallback(
          primary: '/monitor/supervisors',
          fallbacks: const [
            '/admin/supervisors',
          ],
        );
        supervisors = _extractList(json, dataKey: 'supervisors');
      }

      setState(() {
        _supervisors = supervisors;

        if (_supervisors.isEmpty) {
          selectedSupervisorId = null;
        } else {
          final current = selectedSupervisorId;
          if (current == null ||
              !_supervisors.any((s) => (s['employee_id'] ?? '').toString() == current)) {
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
      final end = app.selectedDate;
      final start = end.subtract(const Duration(days: 7));

      String fmt(DateTime d) => d.toIso8601String().substring(0, 10);

      final json = await widget.api.getJson(
        '/monitor/supervisors/$supId/days',
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
      final json = await widget.api.getJson(
        '/monitor/supervisors/$supId/workers',
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

  Future<_Rollup> _getRollup(String workDate) {
    final key = "${selectedSupervisorId ?? ''}|$workDate";
    return _rollupFutureByDate.putIfAbsent(key, () async {
      final supId = selectedSupervisorId;
      if (supId == null || supId.isEmpty) return _Rollup.zero();

      final json = await widget.api.getJson(
        '/monitor/supervisors/$supId/workers',
        query: {'work_date': workDate},
      );
      final workers = _extractList(json, dataKey: 'workers');

      int workerCount = workers.length;
      int openDays = 0;
      int closedDays = 0;

      for (final w in workers) {
        final s = ((w['day_status'] ?? '').toString()).toUpperCase();
        if (s == 'OPEN') openDays++;
        if (s == 'CLOSED' || s == 'FINALIZED') closedDays++;
      }

      int acceptedScans = 0;
      int rejectedScans = 0;

      for (final w in workers) {
        final empId = (w['employee_id'] ?? '').toString();
        if (empId.isEmpty) continue;
        try {
          final day = await widget.api.getJson(
            '/monitor/worker/$empId/day',
            query: {'work_date': workDate},
          );

          final summary = (day is Map && day['summary'] is Map)
              ? Map<String, dynamic>.from(day['summary'])
              : <String, dynamic>{};

          acceptedScans += (summary['accepted_scans'] as num?)?.toInt() ?? 0;
          rejectedScans += (summary['rejected_scans'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }

      return _Rollup(
        workers: workerCount,
        acceptedScans: acceptedScans,
        rejectedScans: rejectedScans,
        openDays: openDays,
        closedDays: closedDays,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final workDate = app.selectedDateStr;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _supervisorsLoading
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: selectedSupervisorId,
                          decoration: const InputDecoration(
                            labelText: 'Supervisor',
                            border: OutlineInputBorder(),
                          ),
                          items: _supervisors.map((s) {
                            final id = (s['employee_id'] ?? '').toString();
                            final name = (s['full_name'] ?? '').toString();
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(name.isEmpty ? id : "$id — $name"),
                            );
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
                OutlinedButton.icon(
                  onPressed: _loadSupervisors,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          if (_supervisorsError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _supervisorsError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const TabBar(
            tabs: [
              Tab(text: 'Days'),
              Tab(text: 'Day Control'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _daysLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _daysError != null
                        ? Center(
                            child: Text(
                              _daysError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _days.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final row = _days[i];
                              final day = _dateOnly((row['work_date'] ?? '').toString());

                              return FutureBuilder<_Rollup>(
                                future: _getRollup(day),
                                builder: (context, snap) {
                                  final rollup = snap.data ?? _Rollup.zero();
                                  return Card(
                                    child: ListTile(
                                      title: Text("Date: $day"),
                                      subtitle: Text(
                                        "Workers: ${rollup.workers} • "
                                        "Accepted: ${rollup.acceptedScans} • "
                                        "Rejected: ${rollup.rejectedScans} • "
                                        "Open: ${rollup.openDays} • "
                                        "Closed: ${rollup.closedDays}",
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: selectedSupervisorId == null
                                          ? null
                                          : () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => SupervisorDayWorkersPage(
                                                    api: widget.api,
                                                    supervisorId: selectedSupervisorId!,
                                                    workDate: day,
                                                    onDataChanged: () async {
                                                      _rollupFutureByDate.clear();
                                                      await _loadDays();
                                                      await _loadControlWorkers();
                                                    },
                                                  ),
                                                ),
                                              );
                                            },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                _controlLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _controlError != null
                        ? Center(
                            child: Text(
                              _controlError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          )
                        : selectedSupervisorId == null
                            ? const Center(child: Text("No supervisor selected"))
                            : SupervisorDayWorkersPage(
                                api: widget.api,
                                supervisorId: selectedSupervisorId!,
                                workDate: workDate,
                                onDataChanged: () async {
                                  _rollupFutureByDate.clear();
                                  await _loadDays();
                                  await _loadControlWorkers();
                                },
                              ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rollup {
  final int workers;
  final int acceptedScans;
  final int rejectedScans;
  final int openDays;
  final int closedDays;

  const _Rollup({
    required this.workers,
    required this.acceptedScans,
    required this.rejectedScans,
    required this.openDays,
    required this.closedDays,
  });

  factory _Rollup.zero() => const _Rollup(
        workers: 0,
        acceptedScans: 0,
        rejectedScans: 0,
        openDays: 0,
        closedDays: 0,
      );
}