import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import 'app_state.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/workers/workers_page.dart';
import '../features/activity/activity_page.dart';
import '../features/supervisors/supervisor_days_page.dart';
import '../features/projects/projects_page.dart';

// If you have admin page(s)
import '../features/admin/employees_admin_page.dart';

// ✅ PM Review pages
import '../features/pm_review/pm_review_page.dart';

class AppShell extends StatefulWidget {
  final ApiClient api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = (app.role).toUpperCase();

    final isAdmin = role == 'ADMIN';
    final isSe = role == 'SE';
    final isPm = role == 'PM';

    // ✅ Role-based menu
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: Text('Workers'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: Text('Activity'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.supervisor_account_outlined),
        selectedIcon: Icon(Icons.supervisor_account),
        label: Text('Supervisors'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.account_tree_outlined),
        selectedIcon: Icon(Icons.account_tree),
        label: Text('Projects'),
      ),

      // ✅ PM Review appears for SE/PM (and you can allow ADMIN too if you want)
      if (isSe || isPm)
        const NavigationRailDestination(
          icon: Icon(Icons.verified_user_outlined),
          selectedIcon: Icon(Icons.verified_user),
          label: Text('PM Review'),
        ),

      // ✅ Admin menu only for ADMIN
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: Text('Admin'),
        ),
    ];

    final pages = <Widget>[
      DashboardPage(api: widget.api),
      WorkersPage(api: widget.api),
      ActivityPage(api: widget.api),
      SupervisorDaysPage(api: widget.api),
      ProjectsPage(api: widget.api),

      if (isSe || isPm) PmReviewPage(api: widget.api),

      if (isAdmin) EmployeesAdminPage(api: widget.api),
    ];

    // Safety: keep index valid when role changes
    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(api: widget.api),
                Expanded(child: pages[_index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ApiClient api;
  const _TopBar({required this.api});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = (app.role).toUpperCase();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text('Role: $role', style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),

          // Date picker (shared app state)
          InkWell(
            onTap: () async {
              final current = DateTime.tryParse(app.workDate) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime(2030, 12, 31),
              );
              if (picked != null) {
                final d = picked.toIso8601String().substring(0, 10);
                app.setWorkDate(d);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(app.workDate),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Logout
          ElevatedButton.icon(
            onPressed: () async {
              await app.logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
