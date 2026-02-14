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

// If you already added PM Review page, keep your import here.
// If you DID NOT create it yet, comment the next two lines.
// import '../features/pm_review/pm_review_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api});
  final ApiClient api;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final role = app.role.toUpperCase().trim();
    final isAdmin = role == 'ADMIN';
    final isPm = role == 'PM';
    final isSe = role == 'SE';
    final isWorker = role == 'WORKER';

    // ✅ Control menu visibility (you can adjust later)
    final canSeeWorkers = isAdmin; // keep strict to avoid SE seeing all employees
    final canSeeActivity = !isWorker || isAdmin || isPm || isSe; // admins/SE/PM ok
    final canSeeSupervisors = isAdmin || isSe || isPm; // SE/PM will use monitor/supervisors
    final canSeeProjects = isAdmin || isSe || isPm;

    final nav = <_NavItem>[
      _NavItem(
        label: 'Dashboard',
        icon: Icons.dashboard,
        page: DashboardPage(api: widget.api),
      ),
      if (canSeeWorkers)
        _NavItem(
          label: 'Workers',
          icon: Icons.people,
          page: WorkersPage(api: widget.api),
        ),
      if (canSeeActivity)
        _NavItem(
          label: 'Activity',
          icon: Icons.list_alt,
          page: ActivityPage(api: widget.api),
        ),
      if (canSeeSupervisors)
        _NavItem(
          label: 'Supervisors',
          icon: Icons.supervisor_account,
          page: SupervisorDaysPage(api: widget.api),
        ),
      if (canSeeProjects)
        _NavItem(
          label: 'Projects',
          icon: Icons.account_tree,
          page: ProjectsPage(api: widget.api),
        ),

      // If you already have PM Review page and want it for SE/PM:
      // if (isPm || isSe)
      //   _NavItem(
      //     label: 'PM Review',
      //     icon: Icons.verified_user,
      //     page: PmReviewPage(api: widget.api),
      //   ),

      if (isAdmin)
        _NavItem(
          label: 'Admin',
          icon: Icons.admin_panel_settings,
          page: EmployeesAdminPage(api: widget.api),
        ),
    ];

    // ✅ Clamp index safely (don’t mutate _index inside build without setState)
    final safeIndex = (_index < nav.length) ? _index : 0;
    if (safeIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = safeIndex);
      });
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: nav
                .map(
                  (n) => NavigationRailDestination(
                    icon: Icon(n.icon),
                    label: Text(n.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: nav[safeIndex].label,
                  role: role,
                  selectedDate: app.selectedDate,
                  onPickDate: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: app.selectedDate,
                      firstDate: DateTime(2025, 1, 1),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      app.setSelectedDate(picked); // ✅ real method in AppState
                    }
                  },
                  onLogout: () => app.logout(),
                ),
                const Divider(height: 1),
                Expanded(child: nav[safeIndex].page),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget page;
  const _NavItem({required this.label, required this.icon, required this.page});
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
        '${selectedDate.year.toString().padLeft(4, '0')}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';

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
