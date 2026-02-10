import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import 'project_tree_page.dart';

class ProjectsPage extends StatefulWidget {
  final ApiClient api;
  const ProjectsPage({super.key, required this.api});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> projects = [];
  String search = '';

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
      final resp = await widget.api.getJson('/projects'); // ✅ let ApiClient add /api/v1

      // resp might be:
      // 1) { projects: [...] }
      // 2) { data: { projects: [...] } } (if old client still used somewhere)
      Map<String, dynamic> data;

      if (resp is Map && resp['projects'] is List) {
        data = (resp as Map).cast<String, dynamic>();
      } else if (resp is Map && resp['data'] is Map) {
        data = (resp['data'] as Map).cast<String, dynamic>();
      } else {
        data = {};
      }

      final list = (data['projects'] as List?) ?? const [];

      projects = list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((p) => (p['project_code'] ?? '').toString().isNotEmpty)
          .toList();
    } catch (e) {
      error = e.toString();
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final filtered = projects.where((p) {
      final s = search.toLowerCase();
      return p.values.any((v) =>
          v != null && v.toString().toLowerCase().contains(s));
    }).toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Projects',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            if (loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              Expanded(
                child: Center(
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No projects found'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          return ListTile(
                            title: Text(
                              p['project_code'] ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(p['project_name'] ?? ''),
                            trailing: Text(p['status'] ?? ''),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProjectTreePage(
                                    api: widget.api,
                                    projectCode: p['project_code'],
                                    projectName: p['project_name'],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
