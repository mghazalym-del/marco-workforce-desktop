import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';
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

  bool _busyAction = false;

  String get _currentRole {
    final app = context.read<AppState>();
    return app.role.toUpperCase().trim();
  }

  String get _currentEmployeeId {
    final app = context.read<AppState>();
    return app.profile?.employeeId ?? "";
  }

  bool get _isPm => _currentRole == "PM";
  bool get _isSe => _currentRole == "SE";

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

  String _fmtDateTime(dynamic v) {
    if (v == null) return "-";
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      final y = dt.year.toString().padLeft(4, "0");
      final m = dt.month.toString().padLeft(2, "0");
      final d = dt.day.toString().padLeft(2, "0");
      final hh = dt.hour.toString().padLeft(2, "0");
      final mm = dt.minute.toString().padLeft(2, "0");
      return "$y-$m-$d $hh:$mm";
    } catch (_) {
      return v.toString();
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, "0");
    final m = now.month.toString().padLeft(2, "0");
    final d = now.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }

  String _taskNameFor(String taskId) {
    try {
      final item = _items.firstWhere((e) => e.code == taskId);
      return item.name;
    } catch (_) {
      return taskId;
    }
  }

  String _friendlyApiError(Object e) {
    final raw = e.toString();

    if (raw.contains('"code":"PARENT_NOT_ACTIVE"')) {
      return "Cannot activate this task because its parent/main task is still inactive.\n\n"
          "Please activate the main task first, then try again.";
    }

    if (raw.contains('"code":"PM_ONLY"')) {
      return "Only the Project Manager can perform this action.";
    }

    if (raw.contains('"code":"INVALID_STATUS"')) {
      return "This action is not allowed for the current task status.";
    }

    if (raw.contains('"code":"TASK_ASSIGNED"')) {
      return "This task is already assigned.\n\n"
          "Unassign it first before deactivating it.";
    }

    if (raw.contains('"code":"ASSIGNEE_NOT_SE"')) {
      return "The selected employee is not recognized by the backend as a Site Engineer (SE).\n\n"
          "Please verify the employee ID and role in the database, then try again.";
    }

    if (raw.contains('"code":"ASSIGNEE_NOT_FOUND"')) {
      return "The selected employee was not found.";
    }

    if (raw.contains('"code":"NOT_LEAF"')) {
      return "Only leaf tasks can be assigned.";
    }

    if (raw.contains('"code":"ACTIVE_RELEASE_EXISTS"')) {
      return "An ACTIVE release already exists for this task and supervisor.\n\n"
          "Close the existing release first, then create a new one.";
    }

    return raw;
  }

  void _popup(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busyAction = false);
      }
    }
  }

  Future<void> _releaseToSupervisor(WorkItemNode n) async {
    final supervisorCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: "0");
    final maxCtrl = TextEditingController();

    final submitted = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Release to Supervisor"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: supervisorCtrl,
                decoration: const InputDecoration(
                  labelText: "Supervisor Employee ID",
                  hintText: "Example: E2001",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Minimum Workers",
                  hintText: "Example: 2",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Maximum Workers",
                  hintText: "Example: 12",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              {
                "supervisor_employee_id": supervisorCtrl.text.trim(),
                "min_workers": minCtrl.text.trim(),
                "max_workers": maxCtrl.text.trim(),
              },
            ),
            child: const Text("Release"),
          ),
        ],
      ),
    );

    if (submitted == null) return;

    final supervisorId = (submitted["supervisor_employee_id"] ?? "").trim();
    final minWorkers = (submitted["min_workers"] ?? "").trim();
    final maxWorkers = (submitted["max_workers"] ?? "").trim();

    if (supervisorId.isEmpty) return;

    await _runAction(() async {
      try {
        final data = await widget.api.postJson(
          "/task-releases",
          body: {
            "project_id": widget.projectCode,
            "task_id": n.code,
            "supervisor_employee_id": supervisorId,
            "min_workers": minWorkers.isEmpty ? 0 : int.tryParse(minWorkers) ?? 0,
            "max_workers": maxWorkers.isEmpty ? null : int.tryParse(maxWorkers),
          },
        );

        final releaseId =
            (data is Map ? data["release_id"] : null)?.toString() ?? "-";

        _popup(
          "Task Released",
          "Project: ${widget.projectCode}\n"
          "Task: ${n.code}\n"
          "Name: ${n.name}\n"
          "Supervisor: $supervisorId\n"
          "Min Workers: ${minWorkers.isEmpty ? "0" : minWorkers}\n"
          "Max Workers: ${maxWorkers.isEmpty ? "-" : maxWorkers}\n"
          "Release ID: $releaseId",
        );

        await _load();
      } catch (e) {
        _popup("Release Failed", _friendlyApiError(e));
      }
    });
  }

  Future<List<Map<String, dynamic>>> _loadReleasesForTask(WorkItemNode n) async {
    final resp = await widget.api.getJson(
      "/task-releases/by-task",
      query: {
        "project_id": widget.projectCode,
        "task_id": n.code,
      },
    );

    if (resp is List) {
      return resp.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }

    if (resp is Map && resp["data"] is List) {
      return (resp["data"] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }

    return [];
  }

  Future<void> _openQrPdfForRelease({
    required WorkItemNode task,
    required Map<String, dynamic> release,
  }) async {
    final supervisorId = release["supervisor_employee_id"]?.toString() ?? "-";
    final supervisorName = release["supervisor_name"]?.toString() ?? "";
    final releaseId = release["release_id"]?.toString() ?? "-";
    final seId = release["se_employee_id"]?.toString() ?? "-";
    final seName = release["se_name"]?.toString() ?? "";
    final minWorkers = release["min_workers"]?.toString() ?? "0";
    final maxWorkers = release["max_workers"]?.toString() ?? "-";

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final qrValue = "$releaseId|$today";

    final fontData = await rootBundle.load("assets/fonts/NotoSans-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: ttf,
        bold: ttf,
      ),
    );

    doc.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                "MARCO Workforce",
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                "Project   : ${widget.projectCode}",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                "Task      : ${task.code}",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                "Task Name : ${task.name}",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                seName.isEmpty
                    ? "Site Engineer: $seId"
                    : "Site Engineer: $seId - $seName",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                supervisorName.isEmpty
                    ? "Supervisor: $supervisorId"
                    : "Supervisor: $supervisorId - $supervisorName",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                "Min Workers: $minWorkers",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.Text(
                "Max Workers: $maxWorkers",
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 24),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrValue,
                width: 220,
                height: 220,
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                "Release ID: $releaseId",
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );

    final bytes = await doc.save();
    final safeTask = task.code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), "_");
    final safeRelease =
        releaseId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), "_");
    final filename =
        "QR_${widget.projectCode}_${safeTask}_${safeRelease}_${DateTime.now().millisecondsSinceEpoch}.pdf";

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("QR PDF prepared: $filename")),
      );
      return;
    }

    final dir = await getApplicationSupportDirectory();
    final filePath = "${dir.path}/$filename";
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    final result = await Process.run("open", [file.path]);
    if (result.exitCode != 0) {
      throw Exception(
        "PDF created but could not open automatically: ${result.stderr}",
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("QR PDF opened: $filePath")),
    );
  }

  Future<void> _showReleasesDialog(WorkItemNode n) async {
    try {
      final releases = await _loadReleasesForTask(n);

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Releases • ${n.code} ${n.name}"),
          content: SizedBox(
            width: 780,
            child: releases.isEmpty
                ? const Text("No releases found for this task.")
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: releases.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final r = releases[i];
                      final supervisorId =
                          r["supervisor_employee_id"]?.toString() ?? "-";
                      final supervisorName =
                          r["supervisor_name"]?.toString() ?? "";
                      final seId = r["se_employee_id"]?.toString() ?? "-";
                      final seName = r["se_name"]?.toString() ?? "";
                      final releaseStatus =
                          r["release_status"]?.toString() ?? "-";
                      final releasedAt = _fmtDateTime(r["released_at"]);
                      final minWorkers =
                          r["min_workers"]?.toString() ?? "0";
                      final maxWorkers =
                          r["max_workers"]?.toString() ?? "-";

                      return ListTile(
                        title: Text(
                          supervisorName.isEmpty
                              ? "Supervisor: $supervisorId"
                              : "Supervisor: $supervisorId - $supervisorName",
                        ),
                        subtitle: Text(
                          "SE: ${seName.isEmpty ? seId : "$seId - $seName"}\n"
                          "Status: $releaseStatus\n"
                          "Released: $releasedAt\n"
                          "Min/Max: $minWorkers / $maxWorkers\n"
                          "Release ID: ${r["release_id"]}",
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text("Open PDF"),
                              onPressed: releaseStatus.toUpperCase() == "ACTIVE"
                                  ? () async {
                                      Navigator.pop(context);
                                      await _openQrPdfForRelease(
                                        task: n,
                                        release: r,
                                      );
                                    }
                                  : null,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.lock_outline),
                              label: const Text("Close"),
                              onPressed: releaseStatus.toUpperCase() == "ACTIVE"
                                  ? () async {
                                      final releaseId =
                                          r["release_id"]?.toString() ?? "";
                                      if (releaseId.isEmpty) return;

                                      await _runAction(() async {
                                        try {
                                          await widget.api.patchJson(
                                            "/task-releases/$releaseId/close",
                                            body: {},
                                          );
                                          if (!mounted) return;
                                          Navigator.pop(context);
                                          _popup(
                                            "Release Closed",
                                            "Task: ${widget.projectCode} / ${n.code}\n"
                                            "Task Name: ${n.name}\n"
                                            "Supervisor: $supervisorId\n"
                                            "Release ID: $releaseId",
                                          );
                                          await _load();
                                        } catch (e) {
                                          if (!mounted) return;
                                          _popup(
                                            "Close Release Failed",
                                            _friendlyApiError(e),
                                          );
                                        }
                                      });
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        ),
      );
    } catch (e) {
      _popup("View Releases Failed", _friendlyApiError(e));
    }
  }

  Future<void> _showCapacityBoard() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _LiveCapacityBoardDialog(
        api: widget.api,
        projectCode: widget.projectCode,
        taskNameFor: _taskNameFor,
        todayStr: _todayStr(),
      ),
    );
  }

  Future<void> _showAssignToSeDialog(WorkItemNode n) async {
    final ctrl = TextEditingController(
      text: n.assignedToEmployeeId ?? "",
    );

    final seId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          n.isAssigned ? "Reassign to Site Engineer" : "Assign to Site Engineer",
        ),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: "SE Employee ID",
            hintText: "E9002",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(n.isAssigned ? "Reassign" : "Assign"),
          ),
        ],
      ),
    );

    if (seId == null || seId.isEmpty) return;

    await _runAction(() async {
      try {
        if (n.isAssigned) {
          await widget.api.postJson(
            "/work-items/${n.id}/unassign",
            body: {},
          );
        }

        await widget.api.postJson(
          "/work-items/${n.id}/assign",
          body: {
            "se_employee_id": seId,
          },
        );

        _popup(
          "Success",
          n.isAssigned ? "Reassigned to $seId" : "Assigned to $seId",
        );
        await _load();
      } catch (e) {
        _popup("Assign Failed", _friendlyApiError(e));
      }
    });
  }

  void _showTaskActions(WorkItemNode n) {
    final isActive = n.isActive;
    final isAssigned = n.isAssigned;
    final isActivatable = n.isInactive;
    final isReleasableByThisSe =
        _isSe && isAssigned && (n.assignedToEmployeeId == _currentEmployeeId);

    final actions = <Widget>[
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text("Task Details"),
        subtitle: Text("${n.code} • ${n.name}"),
        onTap: () {
          Navigator.pop(context);
          _popup(
            "Task Details",
            "Code: ${n.code}\n"
            "Name: ${n.name}\n"
            "Task status: ${n.taskStatus}\n"
            "Plan status: ${n.planStatus}\n"
            "Assigned SE: ${n.assignedToEmployeeId ?? "-"}\n"
            "Assigned By: ${n.assignedBy ?? "-"}\n"
            "Assigned At: ${_fmtDateTime(n.assignedAt)}\n"
            "Activated By: ${n.activatedBy ?? "-"}\n"
            "Activated At: ${_fmtDateTime(n.activatedAt)}",
          );
        },
      ),
    ];

    if (_isPm) {
      actions.addAll([
        ListTile(
          leading: const Icon(Icons.play_circle_fill),
          title: const Text("Activate Task"),
          enabled: isActivatable && !_busyAction,
          onTap: isActivatable && !_busyAction
              ? () async {
                  Navigator.pop(context);
                  await _runAction(() async {
                    try {
                      await widget.api.postJson(
                        "/work-items/${n.id}/activate",
                        body: {},
                      );

                      _popup("Success", "Task Activated");
                      await _load();
                    } catch (e) {
                      _popup("Activation Failed", _friendlyApiError(e));
                    }
                  });
                }
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.stop_circle),
          title: const Text("Deactivate Task"),
          enabled: isActive && !_busyAction,
          onTap: isActive && !_busyAction
              ? () async {
                  Navigator.pop(context);
                  await _runAction(() async {
                    try {
                      await widget.api.postJson(
                        "/work-items/${n.id}/deactivate",
                        body: {},
                      );

                      _popup("Success", "Task Deactivated");
                      await _load();
                    } catch (e) {
                      _popup("Deactivate Failed", _friendlyApiError(e));
                    }
                  });
                }
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.person_add),
          title: Text(isAssigned ? "Reassign to SE" : "Assign to SE"),
          enabled: (isActive || isAssigned) && !_busyAction,
          onTap: (isActive || isAssigned) && !_busyAction
              ? () async {
                  Navigator.pop(context);
                  await _showAssignToSeDialog(n);
                }
              : null,
        ),
        if (isAssigned)
          ListTile(
            leading: const Icon(Icons.person_remove),
            title: const Text("Unassign SE"),
            enabled: !_busyAction,
            onTap: !_busyAction
                ? () async {
                    Navigator.pop(context);
                    await _runAction(() async {
                      try {
                        await widget.api.postJson(
                          "/work-items/${n.id}/unassign",
                          body: {},
                        );

                        _popup("Success", "Task unassigned");
                        await _load();
                      } catch (e) {
                        _popup("Unassign Failed", _friendlyApiError(e));
                      }
                    });
                  }
                : null,
          ),
      ]);
    }

    if (isReleasableByThisSe) {
      actions.add(
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text("Release to Supervisor"),
          enabled: !_busyAction,
          onTap: !_busyAction
              ? () async {
                  Navigator.pop(context);
                  await _releaseToSupervisor(n);
                }
              : null,
        ),
      );
    }

    actions.add(
      ListTile(
        leading: const Icon(Icons.list_alt),
        title: const Text("View Releases"),
        onTap: () {
          Navigator.pop(context);
          _showReleasesDialog(n);
        },
      ),
    );

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: actions),
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
          n.planStatus.toLowerCase().contains(q) ||
          (n.assignedToEmployeeId ?? "").toLowerCase().contains(q);
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
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp =
          await widget.api.getJson("/projects/${widget.projectCode}/tree");

      Map<String, dynamic> data;
      if (resp is Map && resp['items'] is List) {
        data = resp.cast<String, dynamic>();
      } else if (resp is Map && resp['data'] is Map) {
        data = (resp['data'] as Map).cast<String, dynamic>();
      } else {
        data = {};
      }

      final raw = (data["items"] as List?) ?? [];

      final items = raw.map((e) {
        final m = (e as Map).cast<String, dynamic>();
        final id = (m["work_item_id"] ?? "").toString().trim();
        final parent = _parentId(m["parent_work_item_id"]);

        final code = (m["item_code"] ?? "").toString();
        final name = (m["name"] ?? "").toString();

        final planStatus = (m["status"] ?? "").toString();
        final taskStatus = (m["task_status"] ?? "").toString();

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
          assignedToEmployeeId: _parentId(m["assigned_to_employee_id"]),
          assignedBy: _parentId(m["assigned_by"]),
          assignedAt: _dt(m["assigned_at"]),
          activatedBy: _parentId(m["activated_by"]),
          activatedAt: _dt(m["activated_at"]),
        );
      }).where((n) => n.id.isNotEmpty).toList();

      if (!mounted) return;
      setState(() {
        _items = items;
        _applyFilter();
        if (_expanded.isEmpty) {
          _expanded = _allExpandableIds(_items);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
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
          IconButton(
            onPressed: _showCapacityBoard,
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: "Live Workforce Board",
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: "Search (code / name / status / assigned SE)",
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() {
                _q = v;
                _applyFilter();
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: expandable.isEmpty
                      ? null
                      : () => setState(
                            () => _expanded = Set<String>.from(expandable),
                          ),
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
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      : ProjectTreeWidget(
                          items: _filtered,
                          expandedIds: _expanded,
                          onExpandedChanged: (s) => setState(() => _expanded = s),
                          onNodeTap: _showTaskActions,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveCapacityBoardDialog extends StatefulWidget {
  final ApiClient api;
  final String projectCode;
  final String todayStr;
  final String Function(String taskId) taskNameFor;

  const _LiveCapacityBoardDialog({
    required this.api,
    required this.projectCode,
    required this.todayStr,
    required this.taskNameFor,
  });

  @override
  State<_LiveCapacityBoardDialog> createState() =>
      _LiveCapacityBoardDialogState();
}

class _LiveCapacityBoardDialogState extends State<_LiveCapacityBoardDialog> {
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  bool _loading = true;
  Timer? _timer;

  final ScrollController _horizontalCtrl = ScrollController();
  final ScrollController _verticalCtrl = ScrollController();

  Color _capacityColor(String status) {
    switch (status) {
      case "UNDER_MIN":
        return Colors.orange;
      case "FULL":
        return Colors.red;
      case "OVER_CAPACITY":
        return Colors.deepPurple;
      default:
        return Colors.green;
    }
  }

  Color _capacityRowColor(String status, BuildContext context) {
    switch (status) {
      case "UNDER_MIN":
        return Colors.orange.withOpacity(0.08);
      case "FULL":
        return Colors.red.withOpacity(0.08);
      case "OVER_CAPACITY":
        return Colors.deepPurple.withOpacity(0.08);
      default:
        return Theme.of(context).colorScheme.primary.withOpacity(0.04);
    }
  }

  int _countStatus(String status) =>
      _rows.where((r) => (r["capacity_status"]?.toString() ?? "NORMAL") == status).length;

  int _totalCurrentWorkers() => _rows.fold<int>(
        0,
        (sum, r) => sum + (int.tryParse("${r["current_workers"] ?? 0}") ?? 0),
      );

  int _totalAvailableSlots() => _rows.fold<int>(
        0,
        (sum, r) => sum + (int.tryParse("${r["available_slots"] ?? 0}") ?? 0),
      );

  Future<void> _load() async {
    try {
      final resp = await widget.api.getJson(
        "/task-releases/dashboard",
        query: {
          "project_id": widget.projectCode,
          "work_date": widget.todayStr,
        },
      );

      List<Map<String, dynamic>> rows = [];
      if (resp is List) {
        rows = resp.map((e) => (e as Map).cast<String, dynamic>()).toList();
      } else if (resp is Map && resp["data"] is List) {
        rows = (resp["data"] as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _error = null;
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

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _horizontalCtrl.dispose();
    _verticalCtrl.dispose();
    super.dispose();
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
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
    );
  }

  Widget _statusMiniChart() {
    final under = _countStatus("UNDER_MIN");
    final normal = _countStatus("NORMAL");
    final full = _countStatus("FULL");
    final over = _countStatus("OVER_CAPACITY");

    final total = [under, normal, full, over].fold<int>(0, (a, b) => a + b);
    final safeTotal = total == 0 ? 1 : total;

    Widget seg(String label, int value, Color color) {
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
          Text("$label ($value)"),
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
            "Capacity Distribution",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              seg("UNDER_MIN", under, Colors.orange),
              const SizedBox(width: 2),
              seg("NORMAL", normal, Colors.green),
              const SizedBox(width: 2),
              seg("FULL", full, Colors.red),
              const SizedBox(width: 2),
              seg("OVER_CAPACITY", over, Colors.deepPurple),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              legend("Under Min", under, Colors.orange),
              legend("Normal", normal, Colors.green),
              legend("Full", full, Colors.red),
              legend("Over", over, Colors.deepPurple),
              Text("Total: $safeTotal"),
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
            "Current Workers vs Capacity",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            const Text("No active releases.")
          else
            ..._rows.take(6).map((r) {
              final taskId = r["task_id"]?.toString() ?? "-";
              final current = int.tryParse("${r["current_workers"] ?? 0}") ?? 0;
              final min = int.tryParse("${r["min_workers"] ?? 0}") ?? 0;
              final maxRaw = r["max_workers"];
              final max = maxRaw == null ? null : int.tryParse("$maxRaw");
              final denom =
                  (max ?? (current > 0 ? current : min > 0 ? min : 1)).clamp(1, 999999);
              final progress = (current / denom).clamp(0.0, 1.0);
              final status = r["capacity_status"]?.toString() ?? "NORMAL";
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

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final dialogWidth = screen.width * 0.94;
    final dialogHeight = screen.height * 0.84;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Live Workforce Board • ${widget.projectCode} • ${widget.todayStr}",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: "Refresh now",
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: _summaryCard(
                        title: "Active Releases",
                        value: _rows.length.toString(),
                        color: Colors.blue,
                        icon: Icons.task_alt,
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _summaryCard(
                        title: "Current Workers",
                        value: _totalCurrentWorkers().toString(),
                        color: Colors.teal,
                        icon: Icons.groups_2_outlined,
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _summaryCard(
                        title: "Understaffed",
                        value: _countStatus("UNDER_MIN").toString(),
                        color: Colors.orange,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _summaryCard(
                        title: "Full / Over",
                        value: (_countStatus("FULL") +
                                _countStatus("OVER_CAPACITY"))
                            .toString(),
                        color: Colors.red,
                        icon: Icons.report_problem_outlined,
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _summaryCard(
                        title: "Available Slots",
                        value: _totalAvailableSlots().toString(),
                        color: Colors.green,
                        icon: Icons.event_seat_outlined,
                      ),
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
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withOpacity(0.22)),
                    ),
                    child: Scrollbar(
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
                                  DataColumn(label: Text("Task")),
                                  DataColumn(label: Text("Task Name")),
                                  DataColumn(label: Text("SE")),
                                  DataColumn(label: Text("Supervisor")),
                                  DataColumn(label: Text("Current")),
                                  DataColumn(label: Text("Min")),
                                  DataColumn(label: Text("Max")),
                                  DataColumn(label: Text("Available")),
                                  DataColumn(label: Text("Status")),
                                  DataColumn(label: Text("Released")),
                                  DataColumn(label: Text("Load")),
                                ],
                                rows: _rows.map((r) {
                                  final taskId = r["task_id"]?.toString() ?? "-";
                                  final taskName = widget.taskNameFor(taskId);
                                  final seId =
                                      r["se_employee_id"]?.toString() ?? "-";
                                  final seName = r["se_name"]?.toString() ?? "";
                                  final supId =
                                      r["supervisor_employee_id"]?.toString() ??
                                          "-";
                                  final supName =
                                      r["supervisor_name"]?.toString() ?? "";
                                  final current = int.tryParse(
                                          "${r["current_workers"] ?? 0}") ??
                                      0;
                                  final min = int.tryParse(
                                          "${r["min_workers"] ?? 0}") ??
                                      0;
                                  final maxRaw = r["max_workers"];
                                  final max =
                                      maxRaw == null ? null : int.tryParse("$maxRaw");
                                  final available =
                                      r["available_slots"]?.toString() ?? "-";
                                  final status =
                                      r["capacity_status"]?.toString() ?? "NORMAL";
                                  final releasedAtRaw =
                                      r["released_at"]?.toString() ?? "-";
                                  final releasedAt = releasedAtRaw.length > 16
                                      ? releasedAtRaw
                                          .substring(0, 16)
                                          .replaceFirst("T", " ")
                                      : releasedAtRaw;

                                  final denom = (max ??
                                          (current > 0
                                              ? current
                                              : min > 0
                                                  ? min
                                                  : 1))
                                      .clamp(1, 999999);
                                  final progress =
                                      (current / denom).clamp(0.0, 1.0);
                                  final color = _capacityColor(status);

                                  return DataRow(
                                    color: MaterialStatePropertyAll(
                                      _capacityRowColor(status, context),
                                    ),
                                    cells: [
                                      DataCell(Text(taskId)),
                                      DataCell(
                                        SizedBox(
                                          width: 260,
                                          child: Text(
                                            taskName,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 210,
                                          child: Text(
                                            seName.isEmpty
                                                ? seId
                                                : "$seId - $seName",
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
                                                : "$supId - $supName",
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(current.toString())),
                                      DataCell(Text(min.toString())),
                                      DataCell(Text(max?.toString() ?? "-")),
                                      DataCell(Text(available)),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
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
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text("$current / ${max?.toString() ?? "-"}"),
                                              const SizedBox(height: 6),
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: LinearProgressIndicator(
                                                  minHeight: 10,
                                                  value: progress,
                                                  backgroundColor:
                                                      Colors.grey.withOpacity(0.18),
                                                  valueColor:
                                                      AlwaysStoppedAnimation<Color>(
                                                    color,
                                                  ),
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
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "Auto-refresh: 10s",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}