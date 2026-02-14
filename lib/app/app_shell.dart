import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/login_page.dart';
import 'app_state.dart';

// pages
import '../features/dashboard/dashboard_page.dart';
import '../features/workers/workers_page.dart';
import '../features/activity/activity_page.dart';
import '../features/supervisors/supervisor_days_page.dart';
import '../features/projects/projects_page.dart';
import '../features/admin/employees_admin_page.dart';

/// AppShell
/// - Single source of truth for nav + date picker
/// - Role-based menu (Admin page only for ADMIN)
/// - Auth guard: if logged out, show LoginPage (prevents 401 spam)
class AppShell extends StatefulWidget {
  final ApiClient api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget page;
  const _NavItem({required this.label, required this.icon, required this.page});
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  Future<void> _pickDate(BuildContext context, AppState app) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: app.selectedDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null) app.setSelectedDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // 🔐 AUTH GUARD
    if (!app.isLoggedIn) return const LoginPage();

    // AppState.api is nullable by design, but at this point we are logged in.
    final ApiClient api = app.api ?? widget.api;

    final nav = <_NavItem>[
      _NavItem(label: 'Dashboard', icon: Icons.dashboard, page: DashboardPage(api: api)),
      _NavItem(label: 'Workers', icon: Icons.group, page: WorkersPage(api: api)),
      _NavItem(label: 'Activity', icon: Icons.list_alt, page: ActivityPage(api: api)),
      _NavItem(label: 'Supervisors', icon: Icons.supervisor_account, page: SupervisorDaysPage(api: api)),
      _NavItem(label: 'Projects', icon: Icons.account_tree, page: ProjectsPage(api: api)),
      if (app.role == 'ADMIN')
        _NavItem(label: 'Admin', icon: Icons.admin_panel_settings, page: EmployeesAdminPage(api: api)),
    ];

    // If role changes (login/logout) keep index valid
    if (_index >= nav.length) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final item in nav)
                NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: nav[_index].label,
                  role: app.role,
                  selectedDate: app.selectedDate,
                  onPickDate: () => _pickDate(context, app),
                  onLogout: () async {
                    await app.logout();
                    if (!mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (_) => false,
                    );
                  },
                ),
                const Divider(height: 1),
                Expanded(child: nav[_index].page),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String role;
  final DateTime selectedDate;
  final VoidCallback onPickDate;
  final VoidCallback onLogout;

  const _TopBar({
    required this.title,
    required this.role,
    required this.selectedDate,
    required this.onPickDate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text('Role: $role'),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(dateStr),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
