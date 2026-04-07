import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_app/core/widgets/app_action_button.dart';
import 'package:operator_app/core/widgets/app_menu_tile.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_account_management_page.dart';
import 'package:provider/provider.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_presence_debug_page.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_transaction_summary_page.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_profile_header.dart';

class OperatorProfilePage extends StatefulWidget {
  const OperatorProfilePage({super.key});

  @override
  State<OperatorProfilePage> createState() => _OperatorProfilePageState();
}

class _OperatorProfilePageState extends State<OperatorProfilePage> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  String _email = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final operatorRepo = context.read<OperatorRepository>();
      final op = await operatorRepo.getOperator(user.uid);
      _nameController.text = op?.name ?? '';
      _idController.text = op?.operatorId ?? '';
      _email = user.email ?? op?.email ?? '';
    } catch (_) {
      if (!mounted) return;
      showTopError(
        context,
        message: 'Failed to load profile',
        title: 'Profile error',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && context.mounted) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Widget _buildMainProfileMenu() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        AppMenuTile(
          icon: Icons.manage_accounts,
          title: 'Account Management',
          subtitle: 'Update your operator profile details',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const OperatorAccountManagementPage(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        AppMenuTile(
          icon: Icons.receipt_long_outlined,
          title: 'Ride / Transaction Summary',
          subtitle: 'Track rides, earnings, and export income statements',
          onTap: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              showTopInfo(
                context,
                title: 'Not signed in',
                message: 'Sign in again to view transaction summary.',
              );
              return;
            }

            final bookingRepo = context.read<BookingRepository>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => OperatorTransactionSummaryViewModel(
                    bookingRepository: bookingRepo,
                    operatorId: user.uid,
                  ),
                  child: const OperatorTransactionSummaryPage(),
                ),
              ),
            );
          },
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          AppMenuTile(
            icon: Icons.bug_report_outlined,
            title: 'Presence Debug',
            subtitle: 'Inspect operator_presence sync and online state',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OperatorPresenceDebugPage(),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 24),
        AppActionButton(
          label: 'Logout',
          outlined: true,
          foregroundColor: Colors.red,
          borderColor: Colors.red,
          onPressed: () => _logout(context),
          semanticLabel: 'Log out of operator account',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0xFF0066CC),
      ),
      child: Scaffold(
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OperatorProfileHeader(
                    name: _nameController.text.isNotEmpty
                        ? _nameController.text
                        : 'Operator',
                    email: _email,
                    operatorId: _idController.text.isNotEmpty
                        ? 'ID: ${_idController.text}'
                        : 'ID: N/A',
                    topInset: topInset,
                  ),
                  Expanded(child: _buildMainProfileMenu()),
                ],
              ),
      ),
    );
  }
}
