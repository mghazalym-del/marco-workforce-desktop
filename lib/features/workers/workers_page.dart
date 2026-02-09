import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../worker_day/worker_day_page.dart';

class WorkersPage extends StatefulWidget {
  const WorkersPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> workers = [];

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
      // existing backend endpoint
      final list =
          await widget.api.getJsonList('/api/v1/supervisor/workers');
      workers = list.cast<Map<String, dynamic>>();
    } catch (e) {
      error = e.toString();
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: $error'))
              : ListView.separated(
                  itemCount: workers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = workers[i];
                    return ListTile(
                      title:
                          Text('${w['employee_id']} — ${w['full_name']}'),
                      subtitle: Text('Status: ${w['status']}'),
                      onTap: () {
                        final employeeId = (w['employee_id'] ?? '').toString();
                        final fullName = (w['full_name'] ?? '').toString();

                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkerDayPage(
                              api: widget.api,
                              employeeId: employeeId,
                              fullName: fullName,
                              workDate: '', // WorkerDayPage now controls date internally
                            ),
                          ),
                        );
                      },

                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
