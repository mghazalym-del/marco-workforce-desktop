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
    if (!mounted) return;
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

      if (!mounted) return;
      setState(() {
        data = d.isEmpty ? null : d;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _mapList(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<dynamic>()
        .map((e) => e is Map
            ? Map<String, dynamic>.from(e as Map)
            : <String, dynamic>{})
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required BuildContext context,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(child: Text('Error: $error'));
    }
    if (data == null) {
      return const Center(child: Text('No data for the selected date.'));
    }

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

    Color heatColorForAlerts(String type) {
      switch (type) {
        case 'UNDER_MIN':
        case 'OVER_CAPACITY':
        case 'SUPERVISOR_NOT_CLOSED':
        case 'NO_SCAN':
          return Colors.red;
        case 'FULL':
        case 'OPEN_SESSION':
          return Colors.orange;
        default:
          return Colors.green;
      }
    }

    return RefreshIndicator(
      onRefresh: () async => _load(context.read<AppState>().selectedDateStr),
      child: FutureBuilder(
        future: widget.api.getJson(
          '/monitor/se-alerts',
          query: {'work_date': context.read<AppState>().selectedDateStr},
        ),
        builder: (context, snap) {
          List<Map<String, dynamic>> alerts = [];

          if (snap.hasData) {
            final json = snap.data;
            if (json is Map && json['data'] is Map) {
              final dataMap = Map<String, dynamic>.from(json['data'] as Map);
              final raw = dataMap['alerts'];
              if (raw is List) {
                alerts = raw
                    .whereType<dynamic>()
                    .map((e) => e is Map
                        ? Map<String, dynamic>.from(e as Map)
                        : <String, dynamic>{})
                    .where((m) => m.isNotEmpty)
                    .toList();
              }
            }
          }

          final alertCount = alerts.length;
          final openSessionAlerts = alerts
              .where((a) => a['type']?.toString() == 'OPEN_SESSION')
              .length;
          final capacityAlerts = alerts.where((a) {
            final t = a['type']?.toString() ?? '';
            return t == 'UNDER_MIN' || t == 'FULL' || t == 'OVER_CAPACITY';
          }).length;
          final complianceAlerts = alerts.where((a) {
            final t = a['type']?.toString() ?? '';
            return t == 'NO_SCAN' || t == 'SUPERVISOR_NOT_CLOSED';
          }).length;

          final systemHealthColor =
              alertCount > 0 ? Colors.orange : Colors.green;
          final systemHealthText =
              alertCount > 0 ? 'ATTENTION REQUIRED' : 'NORMAL';

          final riskMap = <String, String>{};
          for (final a in alerts) {
            final msg = a['message']?.toString() ?? '';
            final type = a['type']?.toString() ?? '';
            final match = RegExp(r'(PRJ\d+)\/(\d{2}-\d{2})').firstMatch(msg);
            if (match != null) {
              final key = '${match.group(1)}/${match.group(2)}';
              final current = riskMap[key];
              if (current == null) {
                riskMap[key] = type;
              } else {
                final currentColor = heatColorForAlerts(current);
                final newColor = heatColorForAlerts(type);
                if ((newColor == Colors.red && currentColor != Colors.red) ||
                    (newColor == Colors.orange &&
                        currentColor == Colors.green)) {
                  riskMap[key] = type;
                }
              }
            }
          }

          Widget heatLegend(Color color, String label) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(label),
              ],
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (alertCount > 0) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.notifications_active,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'SE Alerts ($alertCount)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ...alerts.take(5).map((a) {
                        final message = a['message']?.toString() ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(message)),
                            ],
                          ),
                        );
                      }),
                      if (alerts.length > 5)
                        Text(
                          '... and ${alerts.length - 5} more alert(s)',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: systemHealthColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: systemHealthColor.withOpacity(0.28),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      alertCount > 0
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle,
                      color: systemHealthColor,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'SYSTEM HEALTH: $systemHealthText',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: systemHealthColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 96,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                children: [
                  _kpiCard(
                    title: 'Open Days',
                    value: openDays.toString(),
                    icon: Icons.lock_open,
                    color: Colors.indigo,
                  ),
                  _kpiCard(
                    title: 'Closed Days',
                    value: closedDays.toString(),
                    icon: Icons.task_alt,
                    color: Colors.green,
                  ),
                  _kpiCard(
                    title: 'Total Scans',
                    value: totalScans.toString(),
                    icon: Icons.qr_code_scanner,
                    color: Colors.blue,
                  ),
                  _kpiCard(
                    title: 'Accepted Scans',
                    value: acceptedScans.toString(),
                    icon: Icons.check_circle_outline,
                    color: Colors.teal,
                  ),
                  _kpiCard(
                    title: 'Rejected Scans',
                    value: rejectedScans.toString(),
                    icon: Icons.cancel_outlined,
                    color: Colors.red,
                  ),
                  _kpiCard(
                    title: 'Offline Scans',
                    value: offlineScans.toString(),
                    icon: Icons.wifi_off,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 96,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                children: [
                  _kpiCard(
                    title: 'Alert Count',
                    value: alertCount.toString(),
                    icon: Icons.notification_important_outlined,
                    color: alertCount > 0 ? Colors.orange : Colors.green,
                  ),
                  _kpiCard(
                    title: 'Live Workers',
                    value: acceptedScans.toString(),
                    icon: Icons.groups_2_outlined,
                    color: Colors.teal,
                  ),
                  _kpiCard(
                    title: 'Open Sessions',
                    value: openSessionAlerts.toString(),
                    icon: Icons.play_circle_outline,
                    color: openSessionAlerts > 0 ? Colors.red : Colors.green,
                  ),
                  _kpiCard(
                    title: 'Tasks At Risk',
                    value: capacityAlerts.toString(),
                    icon: Icons.track_changes_outlined,
                    color:
                        capacityAlerts > 0 ? Colors.deepOrange : Colors.green,
                  ),
                  _kpiCard(
                    title: 'Compliance Issues',
                    value: complianceAlerts.toString(),
                    icon: Icons.rule_folder_outlined,
                    color:
                        complianceAlerts > 0 ? Colors.purple : Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: acceptedScans > 0
                      ? Colors.green.withOpacity(0.08)
                      : Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: acceptedScans > 0 ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      acceptedScans > 0
                          ? Icons.play_circle_fill
                          : Icons.pause_circle,
                      color: acceptedScans > 0 ? Colors.green : Colors.red,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      acceptedScans > 0
                          ? 'WORKFORCE ACTIVE'
                          : 'NO ACTIVITY DETECTED',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _panel(
                context: context,
                title: 'Live Workforce Heat Map',
                child: riskMap.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No active task risks for the selected date.',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              heatLegend(Colors.green, 'Normal'),
                              heatLegend(Colors.orange, 'Watch'),
                              heatLegend(Colors.red, 'Critical'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: riskMap.entries.map((e) {
                              final color = heatColorForAlerts(e.value);
                              final label = e.key;
                              return Container(
                                width: 180,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: color.withOpacity(0.45),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          color: color,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      e.value,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              _panel(
                context: context,
                title: 'Top Tasks',
                child: topTasks.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No task activity for the selected date.',
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(
                            Colors.grey.withOpacity(0.08),
                          ),
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
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workDate = context.watch<AppState>().selectedDateStr;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.withOpacity(0.14)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.black54,
              dividerColor: Colors.transparent,
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
        } else if (resp['data'] is Map &&
            (resp['data'] as Map)['items'] is List) {
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
    } catch (_) {}
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

  int _countStatus(String status) => _rows
      .where((r) => (r['capacity_status']?.toString() ?? 'NORMAL') == status)
      .length;

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.18)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.18)),
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
              final denom = (max ??
                      (current > 0
                          ? current
                          : (min > 0 ? min : 1)))
                  .clamp(1, 999999);
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withOpacity(0.14)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                          child: Text(
                            "${_projectIdOf(p)} - ${_projectNameOf(p)}",
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedProjectId = value);
                      _loadBoard();
                    },
                  ),
                ),
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
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _selectedProjectId = null);
                    _loadBoard();
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Filter'),
                ),
                Text(
                  "Auto-refresh: ${_refreshSeconds}s",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisExtent: 96,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
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
                value:
                    (_countStatus('FULL') + _countStatus('OVER_CAPACITY'))
                        .toString(),
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
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withOpacity(0.14)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Live Workforce Board',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
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
                              headingRowColor: WidgetStatePropertyAll(
                                Colors.grey.withOpacity(0.08),
                              ),
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
                                final projectId =
                                    r['project_id']?.toString() ?? '-';
                                final taskId =
                                    r['task_id']?.toString() ?? '-';
                                final seId =
                                    r['se_employee_id']?.toString() ?? '-';
                                final seName =
                                    r['se_name']?.toString() ?? '';
                                final supId =
                                    r['supervisor_employee_id']?.toString() ??
                                        '-';
                                final supName =
                                    r['supervisor_name']?.toString() ?? '';
                                final current = int.tryParse(
                                        "${r['current_workers'] ?? 0}") ??
                                    0;
                                final min = int.tryParse(
                                        "${r['min_workers'] ?? 0}") ??
                                    0;
                                final maxRaw = r['max_workers'];
                                final max = maxRaw == null
                                    ? null
                                    : int.tryParse("$maxRaw");
                                final available =
                                    r['available_slots']?.toString() ?? '-';
                                final status =
                                    r['capacity_status']?.toString() ??
                                        'NORMAL';
                                final releasedAtRaw =
                                    r['released_at']?.toString() ?? '-';
                                final releasedAt = releasedAtRaw.length > 16
                                    ? releasedAtRaw
                                        .substring(0, 16)
                                        .replaceFirst("T", " ")
                                    : releasedAtRaw;

                                final denom = (max ??
                                        (current > 0
                                            ? current
                                            : (min > 0 ? min : 1)))
                                    .clamp(1, 999999);
                                final progress =
                                    (current / denom).clamp(0.0, 1.0);
                                final color = _capacityColor(status);

                                return DataRow(
                                  color: WidgetStatePropertyAll(
                                    _capacityRowColor(status),
                                  ),
                                  cells: [
                                    DataCell(Text(projectId)),
                                    DataCell(Text(taskId)),
                                    DataCell(
                                      SizedBox(
                                        width: 210,
                                        child: Text(
                                          seName.isEmpty
                                              ? seId
                                              : '$seId - $seName',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: 230,
                                        child: Text(
                                          supName.isEmpty
                                              ? supId
                                              : '$supId - $supName',
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$current / ${max?.toString() ?? "-"}',
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                minHeight: 10,
                                                value: progress,
                                                backgroundColor: Colors.grey
                                                    .withOpacity(0.18),
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(color),
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

class SeAlertsBanner extends StatelessWidget {
  final ApiClient api;
  final String workDate;

  const SeAlertsBanner({
    super.key,
    required this.api,
    required this.workDate,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: api.getJson('/monitor/se-alerts', query: {'work_date': workDate}),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();

        final json = snap.data;
        if (json is! Map || json['data'] == null) return const SizedBox();

        final alerts = json['data']['alerts'] ?? [];
        if (alerts is! List || alerts.isEmpty) return const SizedBox();

        return Card(
          color: Colors.orange.withOpacity(0.15),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: alerts.map<Widget>((a) {
                final m = a is Map ? (a['message']?.toString() ?? '') : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}