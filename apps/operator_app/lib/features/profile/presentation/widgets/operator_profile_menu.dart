import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/app_action_button.dart';
import 'package:operator_app/core/widgets/app_menu_tile.dart';

class OperatorProfileMenu extends StatelessWidget {
  const OperatorProfileMenu({
    super.key,
    required this.isDebugMode,
    required this.onAccountManagement,
    required this.onTransactionSummary,
    required this.onPresenceDebug,
    required this.onLogout,
  });

  final bool isDebugMode;
  final VoidCallback onAccountManagement;
  final VoidCallback onTransactionSummary;
  final VoidCallback onPresenceDebug;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        AppMenuTile(
          icon: Icons.manage_accounts,
          title: 'Account Management',
          subtitle: 'Update your operator profile details',
          onTap: onAccountManagement,
        ),
        const SizedBox(height: 16),
        AppMenuTile(
          icon: Icons.receipt_long_outlined,
          title: 'Ride / Transaction Summary',
          subtitle: 'Track rides, earnings, and export income statements',
          onTap: onTransactionSummary,
        ),
        if (isDebugMode) ...[
          const SizedBox(height: 16),
          AppMenuTile(
            icon: Icons.bug_report_outlined,
            title: 'Presence Debug',
            subtitle: 'Inspect operator_presence sync and online state',
            onTap: onPresenceDebug,
          ),
        ],
        const SizedBox(height: 24),
        AppActionButton(
          label: 'Logout',
          outlined: true,
          foregroundColor: Colors.red,
          borderColor: Colors.red,
          onPressed: onLogout,
          semanticLabel: 'Log out of operator account',
        ),
      ],
    );
  }
}
