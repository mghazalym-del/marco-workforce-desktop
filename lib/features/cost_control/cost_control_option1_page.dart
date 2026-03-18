import 'package:flutter/material.dart';
import 'cost_control_service.dart';

class CostControlOption1Page extends StatefulWidget {
  const CostControlOption1Page({super.key});

  @override
  State<CostControlOption1Page> createState() => _CostControlOption1PageState();
}

class _CostControlOption1PageState extends State<CostControlOption1Page> {
  final CostControlService _service = CostControlService();

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

  @override
  void initState() {
    super.initState();
    _load();
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
      final detail = await _service.fetchOption1Details(
        from: _fromController.text.trim(),
        to: _toController.text.trim(),
        employeeId: _selectedWorker,
        projectId: _selectedProject,
        taskId: _selectedTask,
      );

      final summary = await _service.fetchOption1TaskSummary(
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

  int _sumDetail(String key) {
    return _detailRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row[key]),
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
          title: const Text('Cost Control - Option 1'),
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
                  Expanded(child: _SummaryCard(title: 'Original Total', value: _sumDetail('original_minutes').toString())),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Added Total', value: _sumDetail('added_minutes').toString())),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(title: 'Adjusted Total', value: _sumDetail('adjusted_minutes').toString())),
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
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
                Colors.grey.withValues(alpha: 0.12),
              ),
              columns: const [
                DataColumn(label: Text('Worker')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('Seq')),
                DataColumn(label: Text('Original')),
                DataColumn(label: Text('Added')),
                DataColumn(label: Text('Adjusted')),
                DataColumn(label: Text('Last Task')),
              ],
              rows: _detailRows.map((row) {
                final isLast = row['is_last_scanned_task'] == true;
                return DataRow(
                  color: isLast
                      ? WidgetStatePropertyAll(
                          Colors.amber.withValues(alpha: 0.15),
                        )
                      : null,
                  cells: [
                    DataCell(Text('${row['employee_name'] ?? ''}')),
                    DataCell(Text(_formatDate(row['work_date']))),
                    DataCell(Text('${row['project_id'] ?? ''}')),
                    DataCell(Text('${row['task_id'] ?? ''}')),
                    DataCell(Text('${row['sequence_no'] ?? ''}')),
                    DataCell(Text(_toInt(row['original_minutes']).toString())),
                    DataCell(Text(_toInt(row['added_minutes']).toString())),
                    DataCell(Text(_toInt(row['adjusted_minutes']).toString())),
                    DataCell(
                      Icon(
                        isLast ? Icons.check_circle : Icons.remove,
                        color: isLast ? Colors.green : Colors.grey,
                      ),
                    ),
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
                Colors.grey.withValues(alpha: 0.12),
              ),
              columns: const [
                DataColumn(label: Text('Project')),
                DataColumn(label: Text('Task')),
                DataColumn(label: Text('Rows')),
                DataColumn(label: Text('Original Total')),
                DataColumn(label: Text('Added Total')),
                DataColumn(label: Text('Adjusted Total')),
              ],
              rows: _summaryRows.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text('${row['project_id'] ?? ''}')),
                    DataCell(Text('${row['task_id'] ?? ''}')),
                    DataCell(Text('${row['row_count'] ?? ''}')),
                    DataCell(Text(_toInt(row['total_original_minutes']).toString())),
                    DataCell(Text(_toInt(row['total_added_minutes']).toString())),
                    DataCell(Text(_toInt(row['total_adjusted_minutes']).toString())),
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