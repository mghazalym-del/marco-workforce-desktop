import 'package:flutter/material.dart';
import 'workforce_structure_service.dart';

class WorkforceStructurePage extends StatefulWidget {
  const WorkforceStructurePage({super.key});

  @override
  State<WorkforceStructurePage> createState() => _WorkforceStructurePageState();
}

class _WorkforceStructurePageState extends State<WorkforceStructurePage> {
  final WorkforceStructureService _service = WorkforceStructureService();
  final TextEditingController _projectController =
      TextEditingController(text: 'PRJ001');

  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _tree = [];

  int _pmCount = 0;
  int _seCount = 0;
  int _supervisorCount = 0;
  int _workerCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _projectController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final projectId = _projectController.text.trim();
    if (projectId.isEmpty) {
      setState(() {
        _error = 'Project ID is required.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.fetchProjectTree(projectId: projectId);
      final rawTree = result['tree'] as List? ?? [];

      final parsedTree =
          rawTree.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final counters = _countRoles(parsedTree);

      if (!mounted) return;

      setState(() {
        _data = result;
        _tree = parsedTree;
        _pmCount = counters.pm;
        _seCount = counters.se;
        _supervisorCount = counters.supervisor;
        _workerCount = counters.worker;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _data = null;
        _tree = [];
        _pmCount = 0;
        _seCount = 0;
        _supervisorCount = 0;
        _workerCount = 0;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openReassignDialog(Map<String, dynamic> node) async {
    final employeeId = node['employee_id'];
    final role = (node['role_code'] ?? '').toString().toUpperCase();
    final projectId = _projectController.text.trim();

    // ❌ PM cannot be reassigned
    if (role == 'PM') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PM cannot be reassigned')),
      );
      return;
    }

    List<Map<String, dynamic>> allNodes = [];

    try {
      allNodes = await _service.fetchProjectFlat(projectId: projectId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
      return;
    }

    // 🎯 FILTER VALID TARGETS
    List<Map<String, dynamic>> options = [];

    if (role == 'WORKER') {
      options = allNodes.where((e) => e['role_code'] == 'SUPERVISOR').toList();
    } else if (role == 'SUPERVISOR') {
      options = allNodes.where((e) => e['role_code'] == 'SE').toList();
    } else if (role == 'SE') {
      options = allNodes.where((e) => e['role_code'] == 'PM').toList();
    }

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid reassignment options')),
      );
      return;
    }

    String? selectedId;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Reassign $employeeId'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return DropdownButtonFormField<String>(
                hint: const Text('Select New Manager'),
                value: selectedId,
                items: options.map((e) {
                  return DropdownMenuItem<String>(
                    value: e['employee_id'],
                    child: Text(
                        "${e['employee_name']} (${e['employee_id']})"),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => selectedId = val);
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedId == null) return;
                Navigator.pop(dialogContext, selectedId);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    try {
      await _service.reassign(
        projectId: projectId,
        employeeId: employeeId,
        newManagerId: result,
        updatedBy: 'E4001',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reassigned successfully')),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  _RoleCounters _countRoles(List<Map<String, dynamic>> nodes) {
    int pm = 0;
    int se = 0;
    int supervisor = 0;
    int worker = 0;

    void visit(Map<String, dynamic> node) {
      final role = (node['role_code'] ?? '').toString().toUpperCase();

      switch (role) {
        case 'PM':
          pm++;
          break;
        case 'SE':
          se++;
          break;
        case 'SUPERVISOR':
          supervisor++;
          break;
        case 'WORKER':
          worker++;
          break;
      }

      final children = (node['children'] as List? ?? []);
      for (final child in children) {
        visit(Map<String, dynamic>.from(child as Map));
      }
    }

    for (final n in nodes) {
      visit(n);
    }

    return _RoleCounters(
      pm: pm,
      se: se,
      supervisor: supervisor,
      worker: worker,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectId =
        _data?['project_id']?.toString() ?? _projectController.text.trim();
    final count = _data?['count']?.toString() ?? '0';
    final roots = _data?['roots']?.toString() ?? '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workforce Structure'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _projectController,
                    decoration: const InputDecoration(
                      labelText: 'Project ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Load'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) _buildError(),
            if (_error != null) const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Project',
                    value: projectId,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Nodes',
                    value: count,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Roots',
                    value: roots,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'PM',
                    value: _pmCount.toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'SE',
                    value: _seCount.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Supervisors',
                    value: _supervisorCount.toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Workers',
                    value: _workerCount.toString(),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _tree.isEmpty
                        ? const Center(
                            child: Text('No workforce structure found.'),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: _tree
                                .map(
                                  (node) => _TreeNodeWidget(
                                    node: node,
                                    onReassign: _openReassignDialog,
                                  ),
                                )
                                .toList(),
                          ),
              ),
            ),
          ],
        ),
      ),
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
}

class _TreeNodeWidget extends StatelessWidget {
  final Map<String, dynamic> node;
  final Function(Map<String, dynamic>) onReassign;

  const _TreeNodeWidget({
    required this.node,
    required this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final children = (node['children'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final role = (node['role_code'] ?? '').toString();
    final employeeName = (node['employee_name'] ?? '').toString();
    final employeeId = (node['employee_id'] ?? '').toString();
    final reportsTo = (node['reports_to_employee_name'] ?? '').toString();

    final subtitleParts = <String>[
      employeeId,
      if (reportsTo.isNotEmpty) 'Reports to: $reportsTo',
    ];

    final titleRow = Row(
      children: [
        _RoleBadge(role),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            employeeName.isEmpty ? employeeId : employeeName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (role.toUpperCase() != 'PM')
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Reassign',
            onPressed: () => onReassign(node),
          ),
      ],
    );

    if (children.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: _roleIcon(role),
          title: titleRow,
          subtitle: Text(subtitleParts.join(' • ')),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: _roleIcon(role),
        title: titleRow,
        subtitle: Text(subtitleParts.join(' • ')),
        children: children
            .map(
              (child) => Padding(
                padding: const EdgeInsets.only(left: 20),
                child: _TreeNodeWidget(
                  node: child,
                  onReassign: onReassign,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _roleIcon(String role) {
    switch (role.toUpperCase()) {
      case 'PM':
        return const Icon(Icons.badge);
      case 'SE':
        return const Icon(Icons.engineering);
      case 'SUPERVISOR':
        return const Icon(Icons.supervisor_account);
      case 'WORKER':
        return const Icon(Icons.person);
      default:
        return const Icon(Icons.account_tree);
    }
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge(this.role);

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    switch (role.toUpperCase()) {
      case 'PM':
        bg = Colors.indigo.withValues(alpha: 0.15);
        fg = Colors.indigo;
        break;
      case 'SE':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade700;
        break;
      case 'SUPERVISOR':
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange.shade800;
        break;
      case 'WORKER':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade800;
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
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
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCounters {
  final int pm;
  final int se;
  final int supervisor;
  final int worker;

  _RoleCounters({
    required this.pm,
    required this.se,
    required this.supervisor,
    required this.worker,
  });
}