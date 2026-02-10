import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/login_page.dart';
import '../app/app_state.dart';

// pages
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
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // 🔐 AUTH GUARD: once logged out, never render protected pages
    if (!app.isLoggedIn) {
      return const LoginPage();
    }

    final isAdmin = app.role.toUpperCase() == 'ADMIN';

    // Build pages + nav destinations consistently
    final pages = <Widget>[
      DashboardPage(api: app.api),
      WorkersPage(api: app.api),
      ActivityPage(api: app.api),
      SupervisorDaysPage(api: app.api),
      ProjectsPage(api: app.api),
      if (isAdmin) EmployeesAdminPage(api: app.api),
    ];

    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.group),
        label: Text('Workers'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.list_alt),
        label: Text('Activity'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.supervisor_account),
        label: Text('Supervisors'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.account_tree),
        label: Text('Projects'),
      ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings),
          label: Text('Admin'),
        ),
    ];

    // Safety: if role changed (Admin vs non-Admin), keep index in range
    if (index >= pages.length) index = 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  onLogout: () async {
                    await app.logout();

                    if (!context.mounted) return;

                    // Hard reset navigation stack so no pages call APIs without token
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (_) => false,
                    );
                  },
                ),
                Expanded(child: pages[index]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Future<void> Function() onLogout;
  const _TopBar({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Role: ${app.role}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Spacer(),

          // ✅ Date picker restored
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: app.selectedDate,
                firstDate: DateTime(2025, 1, 1),
                lastDate: DateTime(2035, 12, 31),
              );
              if (picked != null) {
                app.setSelectedDate(picked);
              }
            },
            icon: const Icon(Icons.calendar_today),
            label: Text(app.selectedDateStr),
          ),

          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () async => onLogout(),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
