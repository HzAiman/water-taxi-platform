import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_account_management_page.dart';
import 'package:provider/provider.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_transaction_summary_page.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_profile_header.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_profile_menu.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorProfilePage extends StatefulWidget {
  const OperatorProfilePage({super.key});

  @override
  State<OperatorProfilePage> createState() => _OperatorProfilePageState();
}

class _OperatorProfilePageState extends State<OperatorProfilePage> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  String _email = '';
  String _phoneNumber = '';
  bool _isLoading = true;
  bool _isLoggingOut = false;

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
      _phoneNumber = op?.phoneNumber ?? '';
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
    if (_isLoggingOut) {
      return;
    }
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text(
            'Logging out will set you offline and release accepted bookings back to the queue. Active trips must be completed first.',
          ),
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
      setState(() => _isLoggingOut = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final homeViewModel = context.read<OperatorHomeViewModel>();
          await homeViewModel.ensureInitialized(user.uid);
          final offlineResult = await homeViewModel.goOfflineSafely(
            reason: OfflineReason.logout,
          );
          if (!context.mounted) {
            return;
          }
          if (offlineResult is OperationFailure) {
            _showOperationResult(offlineResult);
            setState(() => _isLoggingOut = false);
            return;
          }
        }
        await FirebaseAuth.instance.signOut();
        if (!context.mounted) {
          return;
        }
        setState(() => _isLoggingOut = false);
        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        _showOperationResult(
          OperationFailure('Logout failed', error.toString()),
        );
        setState(() => _isLoggingOut = false);
      }
    }
  }

  void _showOperationResult(OperationResult result) {
    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: OperatorBrand.magenta,
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
                    phoneNumber: _phoneNumber.isNotEmpty
                        ? _phoneNumber
                        : 'Phone: Not set',
                    topInset: topInset,
                  ),
                  Expanded(
                    child: OperatorProfileMenu(
                      onAccountManagement: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const OperatorAccountManagementPage(),
                          ),
                        );
                      },
                      onTransactionSummary: () {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) {
                          showTopInfo(
                            context,
                            title: 'Not signed in',
                            message:
                                'Sign in again to view transaction summary.',
                          );
                          return;
                        }

                        final bookingRepo = context.read<BookingRepository>();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider(
                              create: (_) =>
                                  OperatorTransactionSummaryViewModel(
                                    bookingRepository: bookingRepo,
                                    operatorId: user.uid,
                                    operatorName:
                                        _nameController.text.trim().isNotEmpty
                                        ? _nameController.text.trim()
                                        : 'Operator',
                                    displayOperatorId:
                                        _idController.text.trim().isNotEmpty
                                        ? _idController.text.trim()
                                        : user.uid,
                                  ),
                              child: const OperatorTransactionSummaryPage(),
                            ),
                          ),
                        );
                      },
                      onLogout: () => _logout(context),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
