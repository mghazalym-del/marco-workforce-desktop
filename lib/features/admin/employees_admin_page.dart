import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class EmployeesAdminPage extends StatefulWidget {
  final ApiClient api;
  const EmployeesAdminPage({super.key, required this.api});

  @override
  State<EmployeesAdminPage> createState() => _EmployeesAdminPageState();
}

class _EmployeesAdminPageState extends State<EmployeesAdminPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> rows = [];
  String q = "";

  final roles = const ["ADMIN", "PM", "SE", "SUPERVISOR", "WORKER"];
  final statuses = const ["Active", "Inactive"];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await widget.api.getJson("/api/v1/admin/employees");
      final list = (res["data"]?["employees"] as List?) ?? [];
      rows = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      error = e.toString();
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _update(String employeeId, Map<String, dynamic> patch) async {
    try {
      await widget.api.patchJson("/api/v1/admin/employees/$employeeId", body: patch);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved")),
      );
    } catch (e) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Update failed"),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = rows.where((r) {
      if (q.trim().isEmpty) return true;
      final s = "${r["employee_id"]} ${r["full_name"]} ${r["role"]}".toLowerCase();
      return s.contains(q.trim().toLowerCase());
    }).toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text("Employees & Roles", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: "Search employee_id / name / role"),
              onChanged: (v) => setState(() => q = v),
            ),
            const SizedBox(height: 12),
            if (loading) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (!loading && error != null)
              Expanded(
                child: Center(
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
              ),
            if (!loading && error == null)
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text("Employee")),
                      DataColumn(label: Text("Role")),
                      DataColumn(label: Text("Status")),
                      DataColumn(label: Text("Is Supervisor")),
                      DataColumn(label: Text("Supervisor ID")),
                      DataColumn(label: Text("Actions")),
                    ],
                    rows: [
                      for (final r in filtered)
                        DataRow(cells: [
                          DataCell(Text("${r["employee_id"]}\n${r["full_name"]}", style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(
                            DropdownButton<String>(
                              value: (r["role"] ?? "WORKER").toString().toUpperCase(),
                              items: roles.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                r["role"] = v;
                                setState(() {});
                              },
                            ),
                          ),
                          DataCell(
                            DropdownButton<String>(
                              value: (r["status"] ?? "Active").toString(),
                              items: statuses.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                r["status"] = v;
                                setState(() {});
                              },
                            ),
                          ),
                          DataCell(
                            Checkbox(
                              value: r["is_supervisor"] == true,
                              onChanged: (v) {
                                r["is_supervisor"] = (v == true);
                                setState(() {});
                              },
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 120,
                              child: TextField(
                                controller: TextEditingController(text: (r["supervisor_employee_id"] ?? "").toString()),
                                onChanged: (v) => r["supervisor_employee_id"] = v.trim().isEmpty ? null : v.trim(),
                                decoration: const InputDecoration(isDense: true, hintText: "E2001"),
                              ),
                            ),
                          ),
                          DataCell(
                            ElevatedButton(
                              onPressed: () => _update(
                                r["employee_id"].toString(),
                                {
                                  "role": r["role"],
                                  "status": r["status"],
                                  "is_supervisor": r["is_supervisor"] == true,
                                  "supervisor_employee_id": r["supervisor_employee_id"],
                                },
                              ),
                              child: const Text("Save"),
                            ),
                          ),
                        ]),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
