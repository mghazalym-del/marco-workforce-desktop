import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../features/activity/activity_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/projects/projects_page.dart';
import '../features/supervisors/supervisor_days_page.dart';
import '../features/workers/workers_page.dart';
import '../features/pm_review/pm_review_page.dart';
import 'app_state.dart';

/// Main app shell (left menu + top bar date + routed pages).
///
/// IMPORTANT:
/// - AppState exposes `selectedDateStr` and `setSelectedDate(DateTime)`.
/// - AppState.api is nullable; AppShell requires a non-null ApiClient.
class AppShell extends StatefulWidget {
  final ApiClient api;
  const AppShell({super.key, required this.api});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _NavItem {
  final String key;
  final IconData icon;
  final String label;
  const _NavItem(this.key, this.icon, this.label);
}

class _AppShellState extends State<AppShell> {
  String _selectedKey = 'dashboard';

  @override
  void initState() {
    super.initState();
    // Ensure AppState has api wired (some pages rely on Provider<AppState>.api).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.api == null) {
        app.setApi(widget.api);
      }
    });
  }

  List<_NavItem> _buildMenu(String role) {
    // Keep the UI simple for now:
    // - ADMIN sees everything
    // - SUPERVISOR sees Supervisors, Activity, Projects, Dashboard, Workers (optional)
    // - SE/PM sees Supervisors (read-only rollups), Activity, Projects, Dashboard, PM Review
    // - WORKER sees Dashboard + Workers (day page from Workers list)
    final items = <_NavItem>[
      const _NavItem('dashboard', Icons.dashboard, 'Dashboard'),
      const _NavItem('workers', Icons.people, 'Workers'),
      const _NavItem('activity', Icons.list_alt, 'Activity'),
      const _NavItem('supervisors', Icons.supervisor_account, 'Supervisors'),
      const _NavItem('projects', Icons.account_tree, 'Projects'),
      const _NavItem('pm_review', Icons.verified_user, 'PM Review'),
    ];

    bool show(String key) {
      if (role == 'ADMIN') return true;
      if (role == 'WORKER') return key == 'dashboard' || key == 'workers';
      if (role == 'SUPERVISOR') return key != 'pm_review'; // supervisor doesn't need PM Review
      // SE / PM:
      if (role == 'SE' || role == 'PM') {
        // Keep Workers visible if you want, but it can leak full employee list.
        // For now: show dashboard/activity/supervisors/projects/pm_review.
        return key == 'dashboard' ||
            key == 'activity' ||
            key == 'supervisors' ||
            key == 'projects' ||
            key == 'pm_review';
      }
      // Default: safe minimal
      return key == 'dashboard';
    }

    final filtered = items.where((i) => show(i.key)).toList();

    // If current selection is not allowed for this role, reset.
    if (!filtered.any((i) => i.key == _selectedKey) && filtered.isNotEmpty) {
      _selectedKey = filtered.first.key;
    }

    return filtered;
  }

  Widget _buildBody(String role) {
    switch (_selectedKey) {
      case 'dashboard':
        return DashboardPage(api: widget.api);
      case 'workers':
        return WorkersPage(api: widget.api);
      case 'activity':
        return ActivityPage(api: widget.api);
      case 'supervisors':
        return SupervisorDaysPage(api: widget.api);
      case 'projects':
        return ProjectsPage(api: widget.api);
      case 'pm_review':
        // Page can be a stub if backend isn't ready yet.
        return PmReviewPage(api: widget.api);
      default:
        return DashboardPage(api: widget.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        final role = (app.profile?.role ?? 'ADMIN').toString();
        final menu = _buildMenu(role);

        return Scaffold(
          body: Row(
            children: [
              // Left menu
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.45),
                  border: Border(
                    right: BorderSide(color: Colors.black.withOpacity(0.06)),
                  ),
                ),
                child: Column(
                  children: [
                    for (final item in menu) ...[
                      _NavButton(
                        icon: item.icon,
                        label: item.label,
                        selected: _selectedKey == item.key,
                        onTap: () => setState(() => _selectedKey = item.key),
                      ),
                      const SizedBox(height: 6),
                    ],
                    const Spacer(),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      role: role,
                      dateStr: app.selectedDateStr,
                      onPickDate: (d) => app.setSelectedDate(d),
                      onLogout: () async {
                        await app.logout();
                        if (!mounted) return;
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                    ),
                    Expanded(child: _buildBody(role)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: selected ? Colors.deepPurple : Colors.black54),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.deepPurple : Colors.black54,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String role;
  final String dateStr;
  final ValueChanged<DateTime> onPickDate;
  final VoidCallback onLogout;

  const _TopBar({
    required this.role,
    required this.dateStr,
    required this.onPickDate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final current = DateTime.tryParse(dateStr) ?? DateTime.now();

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Text('Role: $role', style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(dateStr),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: current,
                firstDate: DateTime(2024, 1, 1),
                lastDate: DateTime(2035, 12, 31),
              );
              if (picked != null) onPickDate(picked);
            },
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
