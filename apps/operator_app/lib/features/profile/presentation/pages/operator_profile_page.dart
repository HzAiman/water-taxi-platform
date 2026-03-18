import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_presence_debug_page.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_transaction_summary_page.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';

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
        _buildMenuButton(
          icon: Icons.manage_accounts,
          title: 'Account Management',
          subtitle: 'Update your operator profile details',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _OperatorAccountManagementRoutePage(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _buildMenuButton(
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
          _buildMenuButton(
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
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red, width: 1.5),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE5F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0066CC)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF7A8AA0)),
            ],
          ),
        ),
      ),
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
                  SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(24, topInset + 24, 24, 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF0066CC),
                            const Color(0xFF0066CC).withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nameController.text.isNotEmpty
                                ? _nameController.text
                                : 'Operator',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _email,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _idController.text.isNotEmpty
                                ? 'ID: ${_idController.text}'
                                : 'ID: N/A',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: _buildMainProfileMenu()),
                ],
              ),
      ),
    );
  }
}

class _OperatorAccountManagementRoutePage extends StatefulWidget {
  const _OperatorAccountManagementRoutePage();

  @override
  State<_OperatorAccountManagementRoutePage> createState() =>
      _OperatorAccountManagementRoutePageState();
}

class _OperatorAccountManagementRoutePageState
    extends State<_OperatorAccountManagementRoutePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final operatorRepo = context.read<OperatorRepository>();
    final op = await operatorRepo.getOperator(user.uid);

    if (!mounted) {
      return;
    }

    setState(() {
      _nameController.text = op?.name ?? '';
      _idController.text = op?.operatorId ?? '';
      _emailController.text = user.email ?? op?.email ?? '';
    });
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final operatorRepo = context.read<OperatorRepository>();
      await operatorRepo.saveProfile(
        uid: user.uid,
        name: _nameController.text,
        email: _emailController.text,
        operatorId: _idController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
      });

      showTopSuccess(context, message: 'Profile updated successfully');
    } catch (e) {
      if (!mounted) {
        return;
      }

      showTopError(
        context,
        message: 'Failed to update profile: ${e.toString()}',
        title: 'Profile update failed',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Full Name',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  enabled: _isEditing,
                  decoration: const InputDecoration(
                    hintText: 'Enter your full name',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (_isEditing && (value == null || value.trim().isEmpty)) {
                      return 'Name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Operator ID',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _idController,
                  enabled: _isEditing,
                  decoration: const InputDecoration(
                    hintText: 'Enter your operator ID',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (_isEditing && (value == null || value.trim().isEmpty)) {
                      return 'Operator ID cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Email Address',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  enabled: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email),
                    hintText: 'Email address',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Email is managed by your login account and cannot be changed here.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                ),
                const SizedBox(height: 28),
                if (!_isEditing)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _isEditing = true);
                      },
                      child: const Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isEditing = false);
                                  await _loadProfile();
                                },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0066CC),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
