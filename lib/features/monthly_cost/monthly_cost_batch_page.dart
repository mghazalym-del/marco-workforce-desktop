import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

class MonthlyCostBatchPage extends StatefulWidget {
  const MonthlyCostBatchPage({super.key});

  @override
  State<MonthlyCostBatchPage> createState() => _MonthlyCostBatchPageState();
}

class _MonthlyCostBatchPageState extends State<MonthlyCostBatchPage> {
  late ApiClient _api;

  bool _initialized = false;
  bool _loadingProjects = false;
  bool _loadingExistingBatch = false;
  bool _validating = false;
  bool _generating = false;
  bool _submitting = false;
  bool _approving = false;
  bool _rejecting = false;

  String? _error;
  String? _actionMessage;

  List<Map<String, dynamic>> _projects = [];
  String? _selectedProjectId;

  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _selectedOption = 'OPTION1';

  Map<String, dynamic>? _validationData;
  Map<String, dynamic>? _generationData;
  Map<String, dynamic>? _batchDetail;
  List<Map<String, dynamic>> _batchList = [];

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

  String _monthValue(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-01";
  }

  String _monthLabel(DateTime d) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${months[d.month - 1]} ${d.year}";
  }

  bool get _hasProject =>
      _selectedProjectId != null && _selectedProjectId!.trim().isNotEmpty;

  bool get _busy =>
      _loadingProjects ||
      _loadingExistingBatch ||
      _validating ||
      _generating ||
      _submitting ||
      _approving ||
      _rejecting;

  String get _currentBatchStatus =>
      _safe((_batchDetail?['batch'] ?? _generationData)?['status'])
          .toUpperCase()
          .trim();

  String? get _currentBatchId {
    final batchNode = _batchDetail?['batch'];
    if (batchNode is Map && batchNode['batch_id'] != null) {
      return _safe(batchNode['batch_id']);
    }
    if (_generationData?['batch_id'] != null) {
      return _safe(_generationData!['batch_id']);
    }
    return null;
  }

  Future<void> _pickMonth() async {
    int tempYear = _selectedMonth.year;
    int tempMonth = _selectedMonth.month;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Select Month'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => setLocal(() => tempYear--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              tempYear.toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setLocal(() => tempYear++),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.2,
                      ),
                      itemBuilder: (_, i) {
                        final month = i + 1;
                        final selected = month == tempMonth;
                        const labels = [
                          'Jan',
                          'Feb',
                          'Mar',
                          'Apr',
                          'May',
                          'Jun',
                          'Jul',
                          'Aug',
                          'Sep',
                          'Oct',
                          'Nov',
                          'Dec'
                        ];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setLocal(() => tempMonth = month),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey.withOpacity(0.2),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, DateTime(tempYear, tempMonth, 1));
                  },
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _validationData = null;
      _generationData = null;
      _batchDetail = null;
      _batchList = [];
      _error = null;
      _actionMessage = null;
    });

    await _loadExistingBatch();
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
          (p) =>
              _safe(p['project_code']).trim() == (nextSelected ?? '').trim(),
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

      if (_hasProject) {
        await _loadExistingBatch();
      }
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

  Future<void> _loadExistingBatch() async {
    if (!_hasProject) return;

    setState(() {
      _loadingExistingBatch = true;
      _error = null;
      _actionMessage = null;
      _generationData = null;
      _batchDetail = null;
      _batchList = [];
    });

    try {
      final res = await _api.getJson(
        '/monthly-cost/batches',
        query: {
          'project_id': _selectedProjectId!.trim(),
          'cost_month': _monthValue(_selectedMonth),
          'option_type': _selectedOption,
        },
      );

      List<Map<String, dynamic>> rows = [];
      if (res is List) {
        rows = res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (res is Map && res['data'] is List) {
        rows = (res['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      setState(() {
        _batchList = rows;
      });

      if (rows.isNotEmpty) {
        await _loadBatchDetail(_safe(rows.first['batch_id']),
            keepActionMessage: false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loadingExistingBatch = false;
      });
    }
  }

  Future<void> _loadBatchDetail(String batchId,
      {bool keepActionMessage = true}) async {
    if (batchId.trim().isEmpty) return;

    try {
      final res = await _api.getJson('/monthly-cost/batches/$batchId');

      Map<String, dynamic>? detail;
      if (res is Map) {
        detail = Map<String, dynamic>.from(res);
      } else if (res is Map && res['data'] is Map) {
        detail = Map<String, dynamic>.from(res['data']);
      }

      if (detail == null) return;

      final Map<String, dynamic> batchNode =
        detail['batch'] is Map
            ? Map<String, dynamic>.from(detail['batch'] as Map)
            : <String, dynamic>{};

      setState(() {
        _batchDetail = detail;
        _generationData = batchNode;
        if (!keepActionMessage) {
          _actionMessage = null;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _validate({bool preserveGenerationData = false}) async {
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
      if (!preserveGenerationData) {
        _generationData = null;
        _batchDetail = null;
        _batchList = [];
      }
    });

    try {
      final body = {
        'project_id': _selectedProjectId!.trim(),
        'cost_month': _monthValue(_selectedMonth),
        'option_type': _selectedOption,
      };

      final res = await _api.postJson(
        '/monthly-cost/validate',
        body: body,
      );

      setState(() {
        _validationData = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _actionMessage = 'Validation completed.';
      });

      if (preserveGenerationData || (_validationData?['ready'] == true)) {
        await _loadExistingBatch();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _validationData = null;
      });
    } finally {
      setState(() {
        _validating = false;
      });
    }
  }

  Future<void> _generate() async {
    if (!_hasProject) {
      setState(() {
        _error = 'Please select a project first.';
      });
      return;
    }

    if (_validationData == null) {
      await _validate();
      if (_validationData == null) return;
    }

    final ready = _validationData?['ready'] == true;
    if (!ready) {
      _showMessage(
        'Generation Blocked',
        'Validation still has blockers. Fix them first, then generate.',
      );
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      final body = {
        'project_id': _selectedProjectId!.trim(),
        'cost_month': _monthValue(_selectedMonth),
        'option_type': _selectedOption,
      };

      final res = await _api.postJson(
        '/monthly-cost/generate',
        body: body,
      );

      setState(() {
        _generationData = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _actionMessage = 'Monthly batch generated successfully.';
      });

      await _validate(preserveGenerationData: true);
      if (_currentBatchId != null) {
        await _loadBatchDetail(_currentBatchId!);
      } else {
        await _loadExistingBatch();
      }
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

  Future<void> _submitBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson('/monthly-cost/batches/$batchId/submit', body: {});
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch submitted to PM successfully.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _approveBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    setState(() {
      _approving = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson(
        '/monthly-cost/batches/$batchId/approve',
        body: {},
      );
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch approved successfully.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _approving = false;
      });
    }
  }

  Future<void> _rejectBatch() async {
    final batchId = _currentBatchId;
    if (batchId == null || batchId.isEmpty) return;

    String reason = '';

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: const Text('Return Batch to Cost Controller'),
              content: TextField(
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (v) => reason = v,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Write the reason for return/reject',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _rejecting = true;
      _error = null;
      _actionMessage = null;
    });

    try {
      await _api.postJson(
        '/monthly-cost/batches/$batchId/reject',
        body: {
          'reason': reason.trim(),
        },
      );
      await _loadExistingBatch();
      await _loadBatchDetail(batchId);
      setState(() {
        _actionMessage = 'Batch returned to Cost Controller.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _rejecting = false;
      });
    }
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
            onChanged: _loadingProjects || _busy
                ? null
                : (value) async {
                    setState(() {
                      _selectedProjectId = value?.trim();
                      _validationData = null;
                      _generationData = null;
                      _batchDetail = null;
                      _batchList = [];
                      _error = null;
                      _actionMessage = null;
                    });
                    await _loadExistingBatch();
                  },
          ),
        ),
        SizedBox(
          width: 180,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _pickMonth,
            icon: const Icon(Icons.calendar_month),
            label: Text(_monthLabel(_selectedMonth)),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            value: _selectedOption,
            decoration: const InputDecoration(
              labelText: 'Option',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'OPTION1', child: Text('OPTION1')),
              DropdownMenuItem(value: 'OPTION2', child: Text('OPTION2')),
            ],
            onChanged: _busy
                ? null
                : (value) async {
                    if (value == null) return;
                    setState(() {
                      _selectedOption = value;
                      _validationData = null;
                      _generationData = null;
                      _batchDetail = null;
                      _batchList = [];
                      _error = null;
                      _actionMessage = null;
                    });
                    await _loadExistingBatch();
                  },
          ),
        ),
        ElevatedButton.icon(
          onPressed: (_busy || !_hasProject) ? null : _validate,
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
          onPressed: (_busy || !_hasProject) ? null : _generate,
          icon: _generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check_circle_outlined),
          label: const Text('Generate'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () async {
            await _loadProjects();
            await _loadExistingBatch();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
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

  Widget _buildValidationSummary() {
    final data = _validationData;
    if (data == null) {
      return const Center(
        child: Text('Run validation to see monthly readiness.'),
      );
    }

    final counts = (data['counts'] is Map)
        ? Map<String, dynamic>.from(data['counts'])
        : <String, dynamic>{};

    final ready = data['ready'] == true;

    return Column(
      children: [
        Row(
          children: [
            _summaryCard(
              title: 'Ready',
              value: ready ? 'YES' : 'NO',
              icon: ready
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Open Sessions',
              value: _safe(counts['open_sessions']).isEmpty
                  ? '0'
                  : _safe(counts['open_sessions']),
              icon: Icons.timelapse,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Unfinalized Days',
              value: _safe(counts['unfinalized_days']).isEmpty
                  ? '0'
                  : _safe(counts['unfinalized_days']),
              icon: Icons.event_busy,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Missing Runs',
              value: _safe(counts['missing_adjustment_runs']).isEmpty
                  ? '0'
                  : _safe(counts['missing_adjustment_runs']),
              icon: Icons.playlist_remove,
            ),
            const SizedBox(width: 12),
            _summaryCard(
              title: 'Blockers',
              value: _safe(counts['blocker_issues']).isEmpty
                  ? '0'
                  : _safe(counts['blocker_issues']),
              icon: Icons.block,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _buildIssuesTable(),
        ),
      ],
    );
  }

  Widget _buildIssuesTable() {
    final data = _validationData;
    final issues = (data != null && data['issues'] is List)
        ? List<Map<String, dynamic>>.from(
            (data['issues'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    if (issues.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: const Center(
          child: Text('No validation issues found.'),
        ),
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                SizedBox(
                    width: 140,
                    child: Text('Type',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 90,
                    child: Text('Severity',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 110,
                    child: Text('Date',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 110,
                    child: Text('Worker',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 110,
                    child: Text('Supervisor',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 110,
                    child: Text('SE',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(
                    width: 100,
                    child: Text('Task',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                    child: Text('Message',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: issues.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (_, i) {
                final m = issues[i];
                final severity = _safe(m['severity']).toUpperCase();
                final severityColor = severity == 'BLOCKER'
                    ? Colors.red
                    : severity == 'WARNING'
                        ? Colors.orange
                        : Colors.blue;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 140, child: Text(_safe(m['issue_type']))),
                      SizedBox(
                        width: 90,
                        child: Text(
                          severity,
                          style: TextStyle(
                            color: severityColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 110, child: Text(_safe(m['work_date']))),
                      SizedBox(width: 110, child: Text(_safe(m['employee_id']))),
                      SizedBox(
                          width: 110,
                          child: Text(_safe(m['supervisor_employee_id']))),
                      SizedBox(
                          width: 110, child: Text(_safe(m['se_employee_id']))),
                      SizedBox(width: 100, child: Text(_safe(m['task_id']))),
                      Expanded(child: Text(_safe(m['message']))),
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

  Widget _buildStatusChip(String status) {
    final s = status.toUpperCase();
    Color fg;
    Color bg;

    switch (s) {
      case 'PM_APPROVED':
        fg = Colors.green.shade700;
        bg = Colors.green.withOpacity(0.10);
        break;
      case 'PM_RETURNED':
        fg = Colors.red.shade700;
        bg = Colors.red.withOpacity(0.10);
        break;
      case 'SUBMITTED':
        fg = Colors.blue.shade700;
        bg = Colors.blue.withOpacity(0.10);
        break;
      case 'GENERATED':
        fg = Colors.orange.shade800;
        bg = Colors.orange.withOpacity(0.10);
        break;
      default:
        fg = Colors.grey.shade800;
        bg = Colors.grey.withOpacity(0.10);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        s.isEmpty ? '-' : s,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildGeneratedSummary() {
    final data = _generationData;
    final detail = _batchDetail;
    final batchNode = detail != null && detail['batch'] is Map
        ? Map<String, dynamic>.from(detail['batch'] as Map)
        : null;
    final totals = detail != null && detail['totals'] is Map
        ? Map<String, dynamic>.from(detail['totals'] as Map)
        : <String, dynamic>{};
    final history = detail != null && detail['history'] is List
        ? List<Map<String, dynamic>>.from(
            (detail['history'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];
        if (data == null && batchNode == null) {
          if (_loadingExistingBatch) {
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(
            child: Text('No monthly batch generated yet.'),
          );
        }

    final role = context.read<AppState>().role.toUpperCase().trim();
    final status = _currentBatchStatus;
    final current = batchNode != null
        ? Map<String, dynamic>.from(batchNode)
        : Map<String, dynamic>.from(data!);

    final canSubmit = role == 'COST_CONTROLLER' &&
        (status == 'GENERATED' || status == 'PM_RETURNED');
    final canApproveReject = role == 'PM' && status == 'SUBMITTED';

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Icon(
                  status == 'PM_APPROVED'
                      ? Icons.check_circle
                      : status == 'PM_RETURNED'
                          ? Icons.cancel
                          : status == 'SUBMITTED'
                              ? Icons.forward_to_inbox
                              : Icons.hourglass_bottom,
                  size: 48,
                  color: status == 'PM_APPROVED'
                      ? Colors.green
                      : status == 'PM_RETURNED'
                          ? Colors.red
                          : status == 'SUBMITTED'
                              ? Colors.blue
                              : Colors.orange,
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Monthly Cost Batch',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: _buildStatusChip(status)),
              const SizedBox(height: 18),
              if (role == 'COST_CONTROLLER')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.18)),
                  ),
                  child: Text(
                    status == 'PM_APPROVED'
                        ? 'PM approved this batch. It is now locked.'
                        : status == 'PM_RETURNED'
                            ? 'PM returned this batch. Please review the reason below, fix if needed, then regenerate and submit again.'
                            : status == 'SUBMITTED'
                                ? 'This batch is waiting for PM review.'
                                : 'This batch is ready for the Cost Controller workflow.',
                    style: TextStyle(color: Colors.blue.shade800),
                  ),
                ),
              Wrap(
                runSpacing: 8,
                spacing: 24,
                children: [
                  SizedBox(
                    width: 380,
                    child: _kv('Batch ID', _safe(current['batch_id'])),
                  ),
                  SizedBox(
                    width: 200,
                    child: _kv('Project', _safe(current['project_id'])),
                  ),
                  SizedBox(
                    width: 180,
                    child: _kv('Month', _safe(current['cost_month'])),
                  ),
                  SizedBox(
                    width: 180,
                    child: _kv('Option', _safe(current['option_type'])),
                  ),
                  SizedBox(
                    width: 180,
                    child: _kv('Inserted Items', _safe(
                      current['inserted_count'] ?? current['item_count'],
                    )),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Generated By', _safe(current['generated_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Generated At', _safe(current['generated_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Submitted By', _safe(current['submitted_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Submitted At', _safe(current['submitted_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Approved By', _safe(current['approved_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Approved At', _safe(current['approved_at'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Returned By', _safe(current['returned_by'])),
                  ),
                  SizedBox(
                    width: 220,
                    child: _kv('Returned At', _safe(current['returned_at'])),
                  ),
                ],
              ),
              if (_safe(current['return_reason']).isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PM Return Reason',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(_safe(current['return_reason'])),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _summaryCard(
                    title: 'Item Count',
                    value: _safe(totals['item_count']),
                    icon: Icons.format_list_numbered,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Original Minutes',
                    value: _safe(totals['original_total_minutes']),
                    icon: Icons.timer_outlined,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Added/Distributed',
                    value: _safe(totals['added_or_distributed_minutes']),
                    icon: Icons.auto_fix_high,
                  ),
                  const SizedBox(width: 12),
                  _summaryCard(
                    title: 'Adjusted Minutes',
                    value: _safe(totals['adjusted_total_minutes']),
                    icon: Icons.fact_check_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (canSubmit)
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitBatch,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.forward_to_inbox),
                      label: const Text('Submit to PM'),
                    ),
                  if (canApproveReject)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: _approving ? null : _approveBatch,
                      icon: _approving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const Text('Approve'),
                    ),
                  if (canApproveReject)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: _rejecting ? null : _rejectBatch,
                      icon: _rejecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.reply),
                      label: const Text('Return to Cost Controller'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Batch History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('No history available yet.'),
                )
              else
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                  ),
                  child: Column(
                    children: history.map((h) {
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(_safe(h['action'])),
                        subtitle: Text(
                          '${_safe(h['actor_id'])} • ${_safe(h['created_at'])}'
                          '${_safe(h['comments']).isNotEmpty ? '\n${_safe(h['comments'])}' : ''}',
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          Flexible(
            child: SelectableText(
              v.isEmpty ? '-' : v,
              style: const TextStyle(fontWeight: FontWeight.w600),
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Monthly Cost Batch'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Validation'),
              Tab(text: 'Generated Batch'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilters(),
              const SizedBox(height: 12),
              _buildStateBanner(),
              if (_error != null || _actionMessage != null)
                const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildValidationSummary(),
                    _buildGeneratedSummary(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}