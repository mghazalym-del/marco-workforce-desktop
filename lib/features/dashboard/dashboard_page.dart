import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.api});
  final ApiClient api;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool loading = true;
  String? error;
  Map<String, dynamic>? data;

  String _lastWorkDate = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
      data = null;
    });

    try {
      final json = await widget.api.getJson(
        '/monitor/dashboard',
        query: {'work_date': workDate},
      );

      Map<String, dynamic> d;
      if (json is Map && json['data'] is Map) {
        d = Map<String, dynamic>.from(json['data'] as Map);
      } else if (json is Map) {
        d = Map<String, dynamic>.from(json as Map);
      } else {
        d = <String, dynamic>{};
      }

      setState(() {
        data = d.isEmpty ? null : d;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Widget _kpi(String title, int value) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(
                value.toString(),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<dynamic>()
        .map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{})
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Widget _buildOverviewTab(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text('Error: $error'));
    if (data == null) return const Center(child: Text('No data for the selected date.'));

    final dayCounts = (data!['day_counts'] is Map)
        ? Map<String, dynamic>.from(data!['day_counts'] as Map)
        : <String, dynamic>{};

    final scanCounts = (data!['scan_counts'] is Map)
        ? Map<String, dynamic>.from(data!['scan_counts'] as Map)
        : <String, dynamic>{};

    final openDays = _asInt(dayCounts['open_days']);
    final closedDays = _asInt(dayCounts['closed_days']);

    final totalScans = _asInt(scanCounts['total_scans']);
    final acceptedScans = _asInt(scanCounts['accepted_scans']);
    final rejectedScans = _asInt(scanCounts['rejected_scans']);
    final offlineScans = _asInt(scanCounts['offline_scans']);

    final topTasksRaw = data!['top_tasks'] ?? const [];
    final topTasks = _mapList(topTasksRaw).map((t) {
      return {
        'project_id': (t['project_id'] ?? '').toString(),
        'task_id': (t['task_id'] ?? '').toString(),
        'scans': _asInt(t['scans']),
      };
    }).toList();

    return RefreshIndicator(
      onRefresh: () async => _load(context.read<AppState>().selectedDateStr),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi('Open Days', openDays),
              _kpi('Closed Days', closedDays),
              _kpi('Total Scans', totalScans),
              _kpi('Accepted Scans', acceptedScans),
              _kpi('Rejected Scans', rejectedScans),
              _kpi('Offline Scans', offlineScans),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top Tasks', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (topTasks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No task activity for the selected date.'),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('project_id')),
                          DataColumn(label: Text('task_id')),
                          DataColumn(label: Text('scans')),
                        ],
                        rows: topTasks.map((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text(r['project_id'].toString())),
                              DataCell(Text(r['task_id'].toString())),
                              DataCell(Text(r['scans'].toString())),
                            ],
                          );
                        }).toList(),
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

  @override
  Widget build(BuildContext context) {
    final workDate = context.watch<AppState>().selectedDateStr;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Live Workforce'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(context),
              _LiveWorkforceTab(
                api: widget.api,
                workDate: workDate,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveWorkforceTab extends StatefulWidget {
  final ApiClient api;
  final String workDate;

  const _LiveWorkforceTab({
    required this.api,
    required this.workDate,
  });

  @override
  State<_LiveWorkforceTab> createState() => _LiveWorkforceTabState();
}

class _LiveWorkforceTabState extends State<_LiveWorkforceTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _projects = [];
  String? _selectedProjectId;
  Timer? _timer;

  int _refreshSeconds = 10;
  final List<int> _refreshOptions = [5, 10, 15, 30, 60];

  final ScrollController _horizontalCtrl = ScrollController();
  final ScrollController _verticalCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _initLoad();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _LiveWorkforceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workDate != widget.workDate) {
      _loadBoard();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _horizontalCtrl.dispose();
    _verticalCtrl.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _refreshSeconds),
      (_) => _loadBoard(),
    );
  }

  Future<void> _initLoad() async {
    await _loadProjects();
    await _loadBoard();
  }

  Future<void> _loadProjects() async {
    try {
      final resp = await widget.api.getJson('/projects');
      debugPrint("PROJECTS RESP => $resp");

      List<Map<String, dynamic>> rows = [];

      if (resp is List) {
        rows = resp.map((e) => (e as Map).cast<String, dynamic>()).toList();
      } else if (resp is Map) {
        if (resp['projects'] is List) {
          rows = (resp['projects'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        } else if (resp['data'] is List) {
          rows = (resp['data'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        } else if (resp['items'] is List) {
          rows = (resp['items'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        } else if (resp['data'] is Map && (resp['data'] as Map)['items'] is List) {
          rows = (((resp['data'] as Map)['items']) as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
        }
      }

      if (!mounted) return;

      String? selected = _selectedProjectId;
      if (selected != null && !rows.any((p) => _projectIdOf(p) == selected)) {
        selected = null;
      }

      setState(() {
        _projects = rows;
        _selectedProjectId = selected;
      });
    } catch (_) {
      // ignore project dropdown failure; board can still load without it
    }
  }

  Future<void> _loadBoard() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = <String, String>{'work_date': widget.workDate};
      if (_selectedProjectId != null && _selectedProjectId!.isNotEmpty) {
        query['project_id'] = _selectedProjectId!;
      }

      final resp = await widget.api.getJson(
        '/task-releases/dashboard',
        query: query,
      );

      List<Map<String, dynamic>> rows = [];
      if (resp is List) {
        rows = resp.map((e) => (e as Map).cast<String, dynamic>()).toList();
      } else if (resp is Map && resp['data'] is List) {
        rows = (resp['data'] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _capacityColor(String status) {
    switch (status) {
      case 'UNDER_MIN':
        return Colors.orange;
      case 'FULL':
        return Colors.red;
      case 'OVER_CAPACITY':
        return Colors.deepPurple;
      default:
        return Colors.green;
    }
  }

  Color _capacityRowColor(String status) {
    switch (status) {
      case 'UNDER_MIN':
        return Colors.orange.withOpacity(0.08);
      case 'FULL':
        return Colors.red.withOpacity(0.08);
      case 'OVER_CAPACITY':
        return Colors.deepPurple.withOpacity(0.08);
      default:
        return Colors.green.withOpacity(0.04);
    }
  }

  int _countStatus(String status) =>
      _rows.where((r) => (r['capacity_status']?.toString() ?? 'NORMAL') == status).length;

  int _totalCurrentWorkers() => _rows.fold<int>(
        0,
        (sum, r) => sum + (int.tryParse("${r['current_workers'] ?? 0}") ?? 0),
      );

  int _totalAvailableSlots() => _rows.fold<int>(
        0,
        (sum, r) => sum + (int.tryParse("${r['available_slots'] ?? 0}") ?? 0),
      );

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.18),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusMiniChart() {
    final under = _countStatus('UNDER_MIN');
    final normal = _countStatus('NORMAL');
    final full = _countStatus('FULL');
    final over = _countStatus('OVER_CAPACITY');

    Widget seg(int value, Color color) {
      final flex = value == 0 ? 1 : value;
      return Expanded(
        flex: flex,
        child: Container(
          height: 18,
          color: color.withOpacity(value == 0 ? 0.12 : 0.85),
        ),
      );
    }

    Widget legend(String label, int value, Color color) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, color: color),
          const SizedBox(width: 6),
          Text('$label ($value)'),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Capacity Distribution',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              seg(under, Colors.orange),
              const SizedBox(width: 2),
              seg(normal, Colors.green),
              const SizedBox(width: 2),
              seg(full, Colors.red),
              const SizedBox(width: 2),
              seg(over, Colors.deepPurple),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              legend('Under Min', under, Colors.orange),
              legend('Normal', normal, Colors.green),
              legend('Full', full, Colors.red),
              legend('Over', over, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskLoadBars() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Workers vs Capacity',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            const Text('No active releases.')
          else
            ..._rows.take(6).map((r) {
              final taskId = r['task_id']?.toString() ?? '-';
              final current = int.tryParse("${r['current_workers'] ?? 0}") ?? 0;
              final min = int.tryParse("${r['min_workers'] ?? 0}") ?? 0;
              final maxRaw = r['max_workers'];
              final max = maxRaw == null ? null : int.tryParse("$maxRaw");
              final denom = (max ?? (current > 0 ? current : (min > 0 ? min : 1))).clamp(1, 999999);
              final progress = (current / denom).clamp(0.0, 1.0);
              final status = r['capacity_status']?.toString() ?? 'NORMAL';
              final color = _capacityColor(status);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$taskId  •  $current / ${max?.toString() ?? "-"}"),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: progress,
                        backgroundColor: Colors.grey.withOpacity(0.18),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _projectIdOf(Map<String, dynamic> p) => (
        p['project_id'] ??
        p['project_code'] ??
        p['code'] ??
        p['projectId'] ??
        p['projectCode'] ??
        ''
      ).toString();

  String _projectNameOf(Map<String, dynamic> p) => (
        p['project_name'] ??
        p['name'] ??
        p['project_name_en'] ??
        p['projectName'] ??
        p['title'] ??
        _projectIdOf(p)
      ).toString();

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    return RefreshIndicator(
      onRefresh: _loadBoard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<String?>(
                  value: _selectedProjectId,
                  decoration: const InputDecoration(
                    labelText: 'Project Filter',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Projects'),
                    ),
                    ..._projects.map(
                      (p) => DropdownMenuItem<String?>(
                        value: _projectIdOf(p),
                        child: Text("${_projectIdOf(p)} - ${_projectNameOf(p)}"),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedProjectId = value);
                    _loadBoard();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  value: _refreshSeconds,
                  decoration: const InputDecoration(
                    labelText: 'Refresh (sec)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _refreshOptions
                      .map(
                        (s) => DropdownMenuItem<int>(
                          value: s,
                          child: Text('$s seconds'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _refreshSeconds = value);
                    _restartTimer();
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _selectedProjectId = null);
                  _loadBoard();
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filter'),
              ),
              const Spacer(),
              Text(
                "Auto-refresh: ${_refreshSeconds}s",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _summaryCard(
                title: 'Active Releases',
                value: _rows.length.toString(),
                color: Colors.blue,
                icon: Icons.task_alt,
              ),
              _summaryCard(
                title: 'Current Workers',
                value: _totalCurrentWorkers().toString(),
                color: Colors.teal,
                icon: Icons.groups_2_outlined,
              ),
              _summaryCard(
                title: 'Understaffed',
                value: _countStatus('UNDER_MIN').toString(),
                color: Colors.orange,
                icon: Icons.warning_amber_rounded,
              ),
              _summaryCard(
                title: 'Full / Over',
                value: (_countStatus('FULL') + _countStatus('OVER_CAPACITY')).toString(),
                color: Colors.red,
                icon: Icons.report_problem_outlined,
              ),
              _summaryCard(
                title: 'Available Slots',
                value: _totalAvailableSlots().toString(),
                color: Colors.green,
                icon: Icons.event_seat_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _statusMiniChart()),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: _taskLoadBars()),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Live Workforce Board',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _loadBoard,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh now',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Scrollbar(
                    controller: _horizontalCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 1500,
                        child: Scrollbar(
                          controller: _verticalCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _verticalCtrl,
                            child: DataTable(
                              columnSpacing: 18,
                              headingRowHeight: 46,
                              dataRowMinHeight: 58,
                              dataRowMaxHeight: 70,
                              columns: const [
                                DataColumn(label: Text('Project')),
                                DataColumn(label: Text('Task')),
                                DataColumn(label: Text('SE')),
                                DataColumn(label: Text('Supervisor')),
                                DataColumn(label: Text('Current')),
                                DataColumn(label: Text('Min')),
                                DataColumn(label: Text('Max')),
                                DataColumn(label: Text('Available')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Released')),
                                DataColumn(label: Text('Load')),
                              ],
                              rows: _rows.map((r) {
                                final projectId = r['project_id']?.toString() ?? '-';
                                final taskId = r['task_id']?.toString() ?? '-';
                                final seId = r['se_employee_id']?.toString() ?? '-';
                                final seName = r['se_name']?.toString() ?? '';
                                final supId = r['supervisor_employee_id']?.toString() ?? '-';
                                final supName = r['supervisor_name']?.toString() ?? '';
                                final current = int.tryParse("${r['current_workers'] ?? 0}") ?? 0;
                                final min = int.tryParse("${r['min_workers'] ?? 0}") ?? 0;
                                final maxRaw = r['max_workers'];
                                final max = maxRaw == null ? null : int.tryParse("$maxRaw");
                                final available = r['available_slots']?.toString() ?? '-';
                                final status = r['capacity_status']?.toString() ?? 'NORMAL';
                                final releasedAtRaw = r['released_at']?.toString() ?? '-';
                                final releasedAt = releasedAtRaw.length > 16
                                    ? releasedAtRaw.substring(0, 16).replaceFirst("T", " ")
                                    : releasedAtRaw;

                                final denom = (max ?? (current > 0 ? current : (min > 0 ? min : 1))).clamp(1, 999999);
                                final progress = (current / denom).clamp(0.0, 1.0);
                                final color = _capacityColor(status);

                                return DataRow(
                                  color: WidgetStatePropertyAll(_capacityRowColor(status)),
                                  cells: [
                                    DataCell(Text(projectId)),
                                    DataCell(Text(taskId)),
                                    DataCell(
                                      SizedBox(
                                        width: 210,
                                        child: Text(
                                          seName.isEmpty ? seId : '$seId - $seName',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 230,
                                        child: Text(
                                          supName.isEmpty ? supId : '$supId - $supName',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text('$current')),
                                    DataCell(Text('$min')),
                                    DataCell(Text(max?.toString() ?? '-')),
                                    DataCell(Text(available)),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(releasedAt)),
                                    DataCell(
                                      SizedBox(
                                        width: 160,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('$current / ${max?.toString() ?? "-"}'),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                minHeight: 10,
                                                value: progress,
                                                backgroundColor: Colors.grey.withOpacity(0.18),
                                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
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
}