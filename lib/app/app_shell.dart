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
import '../features/cost_control/cost_control_option1_page.dart';
import '../features/cost_control/cost_control_option2_page.dart';
import '../features/workforce_structure/workforce_structure_page.dart';
import '../features/task_control/pm_task_control_page.dart';
import '../features/task_control/se_task_control_page.dart';

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
    final role = app.role.toUpperCase().trim();
    final fullName = (app.profile?.fullName ?? '').trim();
    final employeeId = (app.profile?.employeeId ?? '').trim();

    final navItems = <_NavItem>[
      _NavItem(
        label: 'Dashboard',
        icon: Icons.dashboard,
        page: DashboardPage(api: widget.api),
      ),
      _NavItem(
        label: 'Workers',
        icon: Icons.people,
        page: WorkersPage(api: widget.api),
      ),
      _NavItem(
        label: 'Activity',
        icon: Icons.list_alt,
        page: ActivityPage(api: widget.api),
      ),
      _NavItem(
        label: 'Supervisors',
        icon: Icons.supervisor_account,
        page: SupervisorDaysPage(api: widget.api),
      ),
      _NavItem(
        label: 'Projects',
        icon: Icons.account_tree,
        page: ProjectsPage(api: widget.api),
      ),

      // ✅ NEW separate PM screen (does not affect Projects page)
      if (role == 'PM')
        _NavItem(
          label: 'PM Tasks',
          icon: Icons.assignment_outlined,
          page: PmTaskControlPage(api: widget.api),
        ),

      if (role == 'SE')
        _NavItem(
          label: 'SE Tasks',
          icon: Icons.engineering,
          page: SeTaskControlPage(api: widget.api),
        ),

      _NavItem(
        label: 'Admin',
        icon: Icons.admin_panel_settings,
        page: EmployeesAdminPage(api: widget.api),
      ),
      const _NavItem(
        label: 'Cost Opt 1',
        icon: Icons.request_quote,
        page: CostControlOption1Page(),
      ),
      const _NavItem(
        label: 'Cost Opt 2',
        icon: Icons.analytics,
        page: CostControlOption2Page(),
      ),
      const _NavItem(
        label: 'Workforce',
        icon: Icons.account_tree,
        page: WorkforceStructurePage(),
      ),
    ];

    if (_index >= navItems.length) {
      _index = 0;
    }

    final headerUserText = fullName.isNotEmpty
        ? '$fullName${employeeId.isNotEmpty ? ' ($employeeId)' : ''}'
        : (employeeId.isNotEmpty ? employeeId : 'Unknown User');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Row(
        children: [
          Container(
            width: 90,
            color: const Color(0xFF1E293B),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  "MARCO",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                for (int i = 0; i < navItems.length; i++)
                  _RailItem(
                    label: navItems[i].label,
                    icon: navItems[i].icon,
                    selected: _index == i,
                    onTap: () => setState(() => _index = i),
                  ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        navItems[_index].label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),

                      // ✅ user identity
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.18),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headerUserText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              role,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),

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
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/', (_) => false);
                        },
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: navItems[_index].page,
                ),
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

  const _NavItem({
    required this.label,
    required this.icon,
    required this.page,
  });
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
    final fg = selected ? Colors.white : Colors.white70;
    final bg = selected ? Colors.white.withOpacity(0.12) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}