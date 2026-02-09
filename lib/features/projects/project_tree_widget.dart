import 'package:flutter/material.dart';

class WorkItemNode {
  final String id;
  final String? parentId;

  final String code;
  final String name;

  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final int? plannedDurationDays;

  final String planStatus; // work_items.status (e.g. DRAFT)
  final String taskStatus; // work_items.task_status (e.g. ACTIVE/IN_PROGRESS/INACTIVE)

  WorkItemNode({
    required this.id,
    required this.parentId,
    required this.code,
    required this.name,
    required this.plannedStart,
    required this.plannedEnd,
    required this.plannedDurationDays,
    required this.planStatus,
    required this.taskStatus,
  });
}

class ProjectTreeWidget extends StatelessWidget {
  final List<WorkItemNode> items;
  final Set<String> expandedIds;
  final ValueChanged<Set<String>> onExpandedChanged;
  final ValueChanged<WorkItemNode>? onNodeTap;

  const ProjectTreeWidget({
    super.key,
    required this.items,
    required this.expandedIds,
    required this.onExpandedChanged,
    this.onNodeTap,
  });

  Map<String?, List<WorkItemNode>> _groupChildren() {
    final m = <String?, List<WorkItemNode>>{};
    for (final n in items) {
      m.putIfAbsent(n.parentId, () => <WorkItemNode>[]).add(n);
    }
    // stable ordering by item_code
    for (final k in m.keys) {
      m[k]!.sort((a, b) => a.code.compareTo(b.code));
    }
    return m;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return "-";
    return "${d.year.toString().padLeft(4, "0")}-"
        "${d.month.toString().padLeft(2, "0")}-"
        "${d.day.toString().padLeft(2, "0")}";
  }

  String _subtitle(WorkItemNode n) {
    final dur = (n.plannedDurationDays == null) ? "-" : "${n.plannedDurationDays}d";
    final plan = n.planStatus.isEmpty ? "-" : n.planStatus;
    final task = n.taskStatus.isEmpty ? "-" : n.taskStatus;
    return "Task: $task   Plan: $plan   ${_fmtDate(n.plannedStart)} → ${_fmtDate(n.plannedEnd)}   Dur: $dur";
  }

  @override
  Widget build(BuildContext context) {
    final children = _groupChildren();

    final roots = children[null] ?? const <WorkItemNode>[];
    if (roots.isEmpty) {
      return const Center(child: Text("No items found."));
    }

    return ListView.builder(
      itemCount: roots.length,
      itemBuilder: (_, i) => _buildNode(context, roots[i], children, expandedIds, 0),
    );
  }

  Widget _buildNode(
    BuildContext context,
    WorkItemNode n,
    Map<String?, List<WorkItemNode>> children,
    Set<String> expanded,
    int depth,
  ) {
    final kids = children[n.id] ?? const <WorkItemNode>[];
    final hasKids = kids.isNotEmpty;
    final isExpanded = expanded.contains(n.id);

    final leftPad = 12.0 + depth * 18.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: leftPad, right: 12),
          leading: Icon(hasKids ? Icons.account_tree_outlined : Icons.task_alt, size: 18),
          title: Text(
            "${n.code}  ${n.name}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _subtitle(n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: hasKids
              ? IconButton(
                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    final next = Set<String>.from(expanded);
                    if (isExpanded) {
                      next.remove(n.id);
                    } else {
                      next.add(n.id);
                    }
                    onExpandedChanged(next);
                  },
                )
              : null,
          onTap: onNodeTap == null ? null : () => onNodeTap!(n),
        ),
        if (hasKids && isExpanded)
          ...kids.map((k) => _buildNode(context, k, children, expanded, depth + 1)),
      ],
    );
  }
}
