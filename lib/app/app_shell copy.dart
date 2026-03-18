import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import 'app_state.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/workers/workers_page.dart';
import '../features/activity/activity_page.dart';
import '../features/supervisors/supervisor_days_page.dart';
import '../features/projects/projects_page.dart';
import '../features/admin/employees_admin_page.dart';

class AppShell extends StatefulWidget {
  final ApiClient api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  Future<void> _pickDate(AppState app) async {
    final current = app.selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) {
      app.setSelectedDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final pages = <Widget>[
      DashboardPage(api: widget.api),
      WorkersPage(api: widget.api),
      ActivityPage(api: widget.api),
      SupervisorDaysPage(api: widget.api),
      ProjectsPage(api: widget.api),
      EmployeesAdminPage(api: widget.api),
    ];

    final labels = <String>[
      'Dashboard',
      'Workers',
      'Activity',
      'Supervisors',
      'Projects',
      'Admin',
    ];

    final icons = <IconData>[
      Icons.dashboard,
      Icons.people,
      Icons.list_alt,
      Icons.supervisor_account,
      Icons.account_tree,
      Icons.admin_panel_settings,
    ];

    return Scaffold(
      body: Row(
        children: [
          // Left rail
          Container(
            width: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                right: BorderSide(color: Colors.black.withOpacity(0.08)),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                for (int i = 0; i < labels.length; i++)
                  _RailItem(
                    label: labels[i],
                    icon: icons[i],
                    selected: _index == i,
                    onTap: () => setState(() => _index = i),
                  ),
                const Spacer(),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(color: Colors.black.withOpacity(0.08)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        labels[_index],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text('Role: ${app.role}'),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(app),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(app.selectedDateStr),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await app.logout();
                          if (!mounted) return;
                          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                        },
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                ),

                Expanded(child: pages[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : Colors.black54;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
