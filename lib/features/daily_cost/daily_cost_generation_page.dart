import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class DailyCostGenerationPage extends StatefulWidget {
  const DailyCostGenerationPage({super.key});

  @override
  State<DailyCostGenerationPage> createState() => _DailyCostGenerationPageState();
}

class _DailyCostGenerationPageState extends State<DailyCostGenerationPage> {
  late ApiClient _api;

  bool _initialized = false;
  bool _loadingProjects = false;
  bool _validating = false;
  bool _generating = false;

  String? _error;
  String? _actionMessage;

  List<Map<String, dynamic>> _projects = [];
  String? _selectedProjectId;

  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();

  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _generationResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<AppState>().api;

    if (!_initialized) {
      _initialized = true;
      _loadProjects();
    }
  }

  String _safe(dynamic v) => (v ?? '').toString();

  bool get _hasProject =>
      _selectedProjectId != null && _selectedProjectId!.trim().isNotEmpty;

  String _dateText(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;

    setState(() {
      _fromDate = picked;
      if (_toDate.isBefore(_fromDate)) {
        _toDate = _fromDate;
      }
      _rows = [];
      _generationResult = null;
      _error = null;
      _actionMessage = null;
    });
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: _fromDate,
      lastDate: DateTime(2035, 12, 31),
    );
    if (picked == null) return;

    setState(() {
      _toDate = picked;
      _rows = [];
      _generationResult = null;
      _error = null;
      _actionMessage = null;
    });
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loadingProjects = true;
      _error = null;
    });

    try {
      final res = await _api.getJson('/projects');

      List<Map<String, dynamic>> projects = [];
      if (res is Map && res['projects'] is List) {
        projects = (res['projects'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (res is Map && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data']);
        if (data['projects'] is List) {
          projects = (data['projects'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      String? nextSelected = _selectedProjectId;
      if (projects.isNotEmpty) {
        final exists = projects.any(
          (p) => _safe(p['project_code']).trim() == (nextSelected ?? '').trim(),
        );
        if (!exists) {
          nextSelected = _safe(projects.first['project_code']).trim();
        }
      } else {
        nextSelected = null;
      }

      setState(() {
        _projects = projects;
        _selectedProjectId = nextSelected;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _projects = [];
        _selectedProjectId = null;
      });
    } finally {
      setState(() {
        _loadingProjects = false;
      });
    }
  }

  Future<void> _validate() async {
    if (!_hasProject) {
      setState(() {
        _error = 'Please select a project first.';
      });
      return;
    }

    setState(() {
      _validating = true;
      _error = null;
      _actionMessage = null;
      _generationResult = null;
    });

    try {
      final res = await _api.postJson(
        '/daily-cost/validate',
        body: {
          'project_id': _selectedProjectId!.trim(),
          'from': _dateText(_fromDate),
          'to': _dateText(_toDate),
        },
      );

      List<Map<String, dynamic>> rows = [];
      if (res is List) {
        rows = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (res is Map && res['data'] is List) {
        rows = (res['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      setState(() {
        _rows = rows;
        _actionMessage = 'Validation completed.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _rows = [];
      });
    } finally {
      setState(() {
        _validating = false;
      });
    }
  }

  Future<void> _generateAllEligible() async {
    if (!_hasProject) {
      setState(() {
        _error = 'Please select a project first.';
      });
      return;
    }

    if (_rows.isEmpty) {
      await _validate();
      if (_rows.isEmpty) return;
    }

    setState(() {
      _generating = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      final res = await _api.postJson(
        '/daily-cost/generate',
        body: {
          'project_id': _selectedProjectId!.trim(),
          'from': _dateText(_fromDate),
          'to': _dateText(_toDate),
        },
      );

      setState(() {
        _generationResult = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _actionMessage = 'Daily cost generation completed.';
      });

      await _validate();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _generating = false;
      });
    }
  }

  int get _eligibleCount => _rows.where((r) => r['eligible'] == true).length;
  int get _alreadyGeneratedCount =>
      _rows.where((r) => r['blocker_reason']?.toString() == 'ALREADY_GENERATED').length;
  int get _blockedCount => _rows.where((r) => r['eligible'] != true).length;

  Color _statusColor(bool eligible, String reason) {
    if (eligible) return Colors.green;
    if (reason == 'ALREADY_GENERATED') return Colors.blue;
    return Colors.red;
  }

  String _statusText(bool eligible, String reason) {
    if (eligible) return 'ELIGIBLE';
    if (reason.isEmpty) return 'BLOCKED';
    return reason;
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

  Widget _buildStateBanner() {
    if (_error != null) {
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

    if (_actionMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.30)),
        ),
        child: Text(
          _actionMessage!,
          style: TextStyle(color: Colors.green.shade700),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            value: _hasProject ? _selectedProjectId : null,
            decoration: const InputDecoration(
              labelText: 'Project',
              border: OutlineInputBorder(),
            ),
            items: _projects.map((p) {
              final code = _safe(p['project_code']).trim();
              final name = _safe(p['project_name']).trim();
              return DropdownMenuItem<String>(
                value: code,
                child: Text(name.isEmpty ? code : '$code — $name'),
              );
            }).toList(),
            onChanged: _loadingProjects
                ? null
                : (value) {
                    setState(() {
                      _selectedProjectId = value?.trim();
                      _rows = [];
                      _generationResult = null;
                      _error = null;
                      _actionMessage = null;
                    });
                  },
          ),
        ),
        SizedBox(
          width: 160,
          child: OutlinedButton.icon(
            onPressed: _pickFromDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(_dateText(_fromDate)),
          ),
        ),
        SizedBox(
          width: 160,
          child: OutlinedButton.icon(
            onPressed: _pickToDate,
            icon: const Icon(Icons.calendar_month),
            label: Text(_dateText(_toDate)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: (_validating || _generating || !_hasProject) ? null : _validate,
          icon: _validating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.rule_folder_outlined),
          label: const Text('Validate'),
        ),
        FilledButton.icon(
          onPressed: (_validating || _generating || !_hasProject) ? null : _generateAllEligible,
          icon: _generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check_circle_outlined),
          label: const Text('Generate All Eligible'),
        ),
        OutlinedButton.icon(
          onPressed: (_validating || _generating) ? null : _loadProjects,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildGenerationSummary() {
    final data = _generationResult;
    if (data == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.30)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text('Total: ${_safe(data['total'])}'),
          Text('Generated: ${_safe(data['generated'])}'),
          Text('Skipped: ${_safe(data['skipped'])}'),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_rows.isEmpty) {
      return const Center(
        child: Text('Run validation to see eligible daily cost rows.'),
      );
    }

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
                SizedBox(width: 110, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 110, child: Text('Worker', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 140, child: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 120, child: Text('Day Status', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 110, child: Text('Open Sessions', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 140, child: Text('Already Generated', style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 180, child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final r = _rows[i];
                final eligible = r['eligible'] == true;
                final reason = _safe(r['blocker_reason']);
                final color = _statusColor(eligible, reason);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text(_safe(r['work_date']))),
                      SizedBox(width: 110, child: Text(_safe(r['employee_id']))),
                      SizedBox(width: 140, child: Text(_safe(r['employee_name']), overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 120, child: Text(_safe(r['day_status']))),
                      SizedBox(width: 110, child: Text(_safe(r['open_sessions']))),
                      SizedBox(
                        width: 140,
                        child: Text(
                          r['already_generated'] == true ? 'YES' : 'NO',
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: Text(
                          _statusText(eligible, reason),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          reason.isEmpty ? '-' : reason,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
    final role = context.watch<AppState>().role.toUpperCase().trim();

    if (!['COST_CONTROLLER', 'PM'].contains(role)) {
      return const Center(
        child: Text('This page is available only for Cost Controller and PM.'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Cost Generation'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 12),
            _buildStateBanner(),
            if (_error != null || _actionMessage != null) const SizedBox(height: 12),
            _buildGenerationSummary(),
            if (_generationResult != null) const SizedBox(height: 12),
            Row(
              children: [
                _summaryCard(
                  title: 'Rows',
                  value: _rows.length.toString(),
                  icon: Icons.list_alt,
                ),
                const SizedBox(width: 12),
                _summaryCard(
                  title: 'Eligible',
                  value: _eligibleCount.toString(),
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 12),
                _summaryCard(
                  title: 'Already Generated',
                  value: _alreadyGeneratedCount.toString(),
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: 12),
                _summaryCard(
                  title: 'Blocked',
                  value: _blockedCount.toString(),
                  icon: Icons.block,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildTable(),
            ),
          ],
        ),
      ),
    );
  }
}