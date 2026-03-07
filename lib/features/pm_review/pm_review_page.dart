import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../app/app_state.dart';

/// PM/SE Review page (Phase 2.6-A).
///
/// For now this is a **safe stub** so the app compiles and the menu can show the page,
/// while backend endpoints / UI flows are being finalized.
class PmReviewPage extends StatelessWidget {
  final ApiClient api;
  const PmReviewPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = (app.profile?.role ?? '').toString();
    final dateStr = app.selectedDateStr;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PM Review',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('Role: $role   •   Work date: $dateStr'),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: const Text(
              'This page will be enabled in Phase 2.6-A once the backend review endpoints are finalized.\n\n'
              'Next planned capabilities:\n'
              '• View worker task sessions (not only total hours)\n'
              '• Approve / Reject / Return to Supervisor for correction\n',
            ),
          ),
        ],
      ),
    );
  }
}
