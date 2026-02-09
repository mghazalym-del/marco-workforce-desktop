import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import 'project_tree_widget.dart';

class ProjectTreePage extends StatefulWidget {
  final ApiClient api;
  final String projectCode;
  final String projectName;

  const ProjectTreePage({
    super.key,
    required this.api,
    required this.projectCode,
    required this.projectName,
  });

  @override
  State<ProjectTreePage> createState() => _ProjectTreePageState();
}

class _ProjectTreePageState extends State<ProjectTreePage> {
  bool _loading = true;
  String? _error;

  List<WorkItemNode> _items = [];
  List<WorkItemNode> _filtered = [];

  Set<String> _expanded = {};
  String _q = "";

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  String? _parentId(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == "null") return null;
    return s;
  }

  void _popup(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
      ),
    );
  }

  void _applyFilter() {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List<WorkItemNode>.from(_items);
      return;
    }
    _filtered = _items.where((n) {
      return n.code.toLowerCase().contains(q) ||
          n.name.toLowerCase().contains(q) ||
          n.taskStatus.toLowerCase().contains(q) ||
          n.planStatus.toLowerCase().contains(q);
    }).toList();
  }

  Set<String> _allExpandableIds(List<WorkItemNode> list) {
    final hasChild = <String, bool>{};
    for (final n in list) {
      hasChild[n.id] = hasChild[n.id] ?? false;
    }
    for (final n in list) {
      if (n.parentId != null) {
        hasChild[n.parentId!] = true;
      }
    }
    final ids = <String>{};
    hasChild.forEach((id, v) {
      if (v == true) ids.add(id);
    });
    return ids;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // IMPORTANT: your ApiClient supports getJson(path)
      final resp = await widget.api.getJson("/api/v1/projects/${widget.projectCode}/tree");

      if (resp["success"] != true) {
        throw Exception(resp["error"]?["message"] ?? "Failed to load tree");
      }

      final data = (resp["data"] as Map?)?.cast<String, dynamic>() ?? {};
      final raw = (data["items"] as List?) ?? [];

      final items = raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        final id = (m["work_item_id"] ?? "").toString().trim();
        final parent = _parentId(m["parent_work_item_id"]);

        final code = (m["item_code"] ?? "").toString();
        final name = (m["name"] ?? "").toString();

        final planStatus = (m["status"] ?? "").toString(); // DRAFT etc.
        final taskStatus = (m["task_status"] ?? "").toString(); // ACTIVE/IN_PROGRESS/INACTIVE...

        int? dur;
        final pd = m["planned_duration_days"];
        if (pd is int) dur = pd;
        if (dur == null) dur = int.tryParse((pd ?? "").toString());

        return WorkItemNode(
          id: id,
          parentId: parent,
          code: code,
          name: name,
          plannedStart: _dt(m["planned_start"]),
          plannedEnd: _dt(m["planned_end"]),
          plannedDurationDays: dur,
          planStatus: planStatus,
          taskStatus: taskStatus,
        );
      }).where((n) => n.id.isNotEmpty).toList();

      setState(() {
        _items = items;
        _applyFilter();

        // keep expanded if user already expanded; otherwise expand all top-level by default (optional)
        if (_expanded.isEmpty) {
          _expanded = _allExpandableIds(_items); // expand all by default
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final expandable = _allExpandableIds(_items);

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.projectCode} • ${widget.projectName}"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: "Search (code / name / status)",
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() {
                _q = v;
                _applyFilter();
              }),
            ),
            const SizedBox(height: 8),

            // Expand/Collapse controls restored
            Row(
              children: [
                OutlinedButton(
                  onPressed: expandable.isEmpty
                      ? null
                      : () => setState(() => _expanded = Set<String>.from(expandable)),
                  child: const Text("Expand all"),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _expanded = {}),
                  child: const Text("Collapse all"),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_error != null)
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : ProjectTreeWidget(
                          items: _filtered,
                          expandedIds: _expanded,
                          onExpandedChanged: (s) => setState(() => _expanded = s),
                          onNodeTap: (n) => _popup(
                            "Task Details",
                            "Code: ${n.code}\n"
                            "Name: ${n.name}\n"
                            "Task status: ${n.taskStatus}\n"
                            "Plan status: ${n.planStatus}",
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
