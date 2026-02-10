import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_client.dart';
import '../../app/app_state.dart';

class ActivityPage extends StatefulWidget {
  final ApiClient api;
  const ActivityPage({super.key, required this.api});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  String _lastWorkDate = '';

  @override
  void initState() {
    super.initState();
    // initial load will happen from didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workDate = context.watch<AppState>().selectedDateStr;
    if (workDate != _lastWorkDate) {
      _lastWorkDate = workDate;
      _load(workDate);
    }
  }

  Future<void> _load(String workDate) async {
    setState(() {
      loading = true;
      error = null;
      items = [];
    });

    try {
      final res = await widget.api.getJson(
        '/monitor/activity/projects',
        query: {'work_date': workDate},
      );

      // ApiClient.getJson returns "data" (per our earlier fixes),
      // so res might already be the data node.
      // Accept multiple shapes safely:
      // - { activity: [ ... ] }
      // - { items: [ ... ] }
      // - { projects: [ ... ] }
      // - [ ... ]
      List list = [];
      if (res is List) {
        list = res;
      } else if (res is Map) {
        final a = res['activity'];
        final it = res['items'];
        final prj = res['projects'];

        if (a is List) list = a;
        else if (it is List) list = it;
        else if (prj is List) list = prj;
        else {
          // last resort: first list found
          for (final v in res.values) {
            if (v is List) {
              list = v;
              break;
            }
          }
        }
      }

      final parsed = list
          .whereType<dynamic>()
          .map((e) => (e is Map)
              ? Map<String, dynamic>.from(e as Map)
              : <String, dynamic>{'value': e})
          .toList();

      setState(() {
        items = parsed;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String _titleOf(Map<String, dynamic> m) {
    // Common backend keys (we try best effort)
    return (m['project_name'] ??
            m['project'] ??
            m['name'] ??
            m['title'] ??
            'Activity')
        .toString();
  }

  String _subtitleOf(Map<String, dynamic> m) {
    // Show useful details if present
    final parts = <String>[];

    final workers = m['workers_count'] ?? m['workers'];
    if (workers != null) parts.add('Workers: $workers');

    final scansA = m['accepted_scans'];
    final scansR = m['rejected_scans'];
    if (scansA != null || scansR != null) {
      parts.add('Scans: ${scansA ?? 0} accepted / ${scansR ?? 0} rejected');
    }

    final first = m['first_activity'];
    final last = m['last_activity'];
    if (first != null || last != null) {
      parts.add('First: ${first ?? "-"}  Last: ${last ?? "-"}');
    }

    // If nothing matched, just dump a short snippet:
    if (parts.isEmpty) {
      final s = m.entries
          .take(3)
          .map((e) => '${e.key}=${e.value}')
          .join(' • ');
      return s.isEmpty ? '' : s;
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(child: Text(error!));
    }
    if (items.isEmpty) {
      return const Center(child: Text('No activity for the selected date.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = items[i];
        return Card(
          child: ListTile(
            title: Text(_titleOf(m)),
            subtitle: Text(_subtitleOf(m)),
          ),
        );
      },
    );
  }
}
