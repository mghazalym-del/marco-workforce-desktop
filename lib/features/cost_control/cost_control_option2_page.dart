import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import 'cost_control_service.dart';

class CostControlOption2Page extends StatefulWidget {
  const CostControlOption2Page({super.key});

  @override
  State<CostControlOption2Page> createState() => _CostControlOption2PageState();
}

class _CostControlOption2PageState extends State<CostControlOption2Page> {
  late CostControlService _service;

  final TextEditingController _fromController =
      TextEditingController(text: '2026-03-01');
  final TextEditingController _toController =
      TextEditingController(text: '2026-03-31');

  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _detailRows = [];
  List<Map<String, dynamic>> _summaryRows = [];

  String? _selectedWorker;
  String? _selectedProject;
  String? _selectedTask;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = CostControlService(context.read<AppState>().api);

    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _service.fetchOption2Details(
        from: _fromController.text.trim(),
        to: _toController.text.trim(),
        employeeId: _selectedWorker,
        projectId: _selectedProject,
        taskId: _selectedTask,
      );

      final summary = await _service.fetchOption2TaskSummary(
        from: _fromController.text.trim(),
        to: _toController.text.trim(),
        employeeId: _selectedWorker,
        projectId: _selectedProject,
        taskId: _selectedTask,
      );

      setState(() {
        _detailRows = detail;
        _summaryRows = summary;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _detailRows = [];
        _summaryRows = [];
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  List<String> _workers() {
    final set = <String>{};
    for (final row in _detailRows) {
      final v = row['employee_id']?.toString();
      if (v != null && v.isNotEmpty) set.add(v);
    }
    return set.toList()..sort();
  }

  List<String> _projects() {
    final set = <String>{};
    for (final row in _detailRows) {
      final v = row['project_id']?.toString();
      if (v != null && v.isNotEmpty) set.add(v);
    }
    return set.toList()..sort();
  }

  List<String> _tasks() {
    final set = <String>{};
    for (final row in _detailRows) {
      final project = row['project_id']?.toString();
      if (_selectedProject != null && _selectedProject != project) continue;
      final v = row['task_id']?.toString();
      if (v != null && v.isNotEmpty) set.add(v);
    }
    return set.toList()..sort();
  }

  double _sumDetail(String key) {
    return _detailRows.fold<double>(
      0,
      (sum, row) => sum + _toDouble(row[key]),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedWorker = null;
      _selectedProject = null;
      _selectedTask = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cost Control - Option 2'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Detail'),
              Tab(text: 'Task Summary'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilters(),
              const SizedBox(height: 16),
              if (_error != null) _buildError(),
              if (_error != null) const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SummaryCard(title: 'Rows', value: _detailRows.length.toString())),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Original Total', value: _sumDetail('original_minutes').toStringAsFixed(0))),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Distributed Total', value: _sumDetail('distributed_minutes').toStringAsFixed(2))),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Adjusted Total', value: _sumDetail('adjusted_minutes').toStringAsFixed(2))),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildDetailTable(),
                    _buildSummaryTable(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final workers = _workers();
    final projects = _projects();
    final tasks = _tasks();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: _fromController,
            decoration: const InputDecoration(
              labelText: 'From',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: _toController,
            decoration: const InputDecoration(
              labelText: 'To',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _selectedWorker,
            decoration: const InputDecoration(
              labelText: 'Worker',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All'),
              ),
              ...workers.map(
                (e) => DropdownMenuItem<String?>(
                  value: e,
                  child: Text(e),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedWorker = value;
              });
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _selectedProject,
            decoration: const InputDecoration(
              labelText: 'Project',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All'),
              ),
              ...projects.map(
                (e) => DropdownMenuItem<String?>(
                  value: e,
                  child: Text(e),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedProject = value;
                _selectedTask = null;
              });
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _selectedTask,
            decoration: const InputDecoration(
              labelText: 'Task',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All'),
              ),
              ...tasks.map(
                (e) => DropdownMenuItem<String?>(
                  value: e,
                  child: Text(e),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedTask = value;
              });
            },
          ),
        ),
        ElevatedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Load'),
        ),
        OutlinedButton(
          onPressed: _loading ? null : _clearFilters,
          child: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.30)),
      ),
      child: Text(
        _error!,
        style: TextStyle(color: Colors.red.shade700),
      ),
    );
  }

  Widget _buildDetailTable() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_detailRows.isEmpty) return const Center(child: Text('No data found.'));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                Colors.grey.withOpacity(0.12),
              ),
              columns: const [
                DataColumn(label: Text('Worker')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('Seq')),
                DataColumn(label: Text('Original')),
                DataColumn(label: Text('Distributed')),
                DataColumn(label: Text('Adjusted')),
              ],
              rows: _detailRows.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text('${row['employee_name'] ?? ''}')),
                    DataCell(Text(_formatDate(row['work_date']))),
                    DataCell(Text('${row['project_id'] ?? ''}')),
                    DataCell(Text('${row['task_id'] ?? ''}')),
                    DataCell(Text('${row['sequence_no'] ?? ''}')),
                    DataCell(Text(_toInt(row['original_minutes']).toString())),
                    DataCell(Text(_toDouble(row['distributed_minutes']).toStringAsFixed(2))),
                    DataCell(Text(_toDouble(row['adjusted_minutes']).toStringAsFixed(2))),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTable() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_summaryRows.isEmpty) return const Center(child: Text('No data found.'));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                Colors.grey.withOpacity(0.12),
              ),
              columns: const [
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('Rows')),
                DataColumn(label: Text('Original Total')),
                DataColumn(label: Text('Distributed Total')),
                DataColumn(label: Text('Adjusted Total')),
              ],
              rows: _summaryRows.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text('${row['project_id'] ?? ''}')),
                    DataCell(Text('${row['task_id'] ?? ''}')),
                    DataCell(Text('${row['row_count'] ?? ''}')),
                    DataCell(Text(_toInt(row['total_original_minutes']).toString())),
                    DataCell(Text(_toDouble(row['total_distributed_minutes']).toStringAsFixed(2))),
                    DataCell(Text(_toDouble(row['total_adjusted_minutes']).toStringAsFixed(2))),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    final text = value.toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;

  const _SummaryCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}