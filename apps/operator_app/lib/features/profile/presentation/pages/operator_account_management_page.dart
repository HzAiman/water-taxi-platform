import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/app_action_button.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:provider/provider.dart';

class OperatorAccountManagementPage extends StatefulWidget {
  const OperatorAccountManagementPage({super.key});

  @override
  State<OperatorAccountManagementPage> createState() =>
      _OperatorAccountManagementPageState();
}

class _OperatorAccountManagementPageState
    extends State<OperatorAccountManagementPage> {
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
                  AppActionButton(
                    label: 'Edit Profile',
                    onPressed: () {
                      setState(() => _isEditing = true);
                    },
                    semanticLabel: 'Edit operator profile',
                  )
                else
                  Column(
                    children: [
                      AppActionButton(
                        label: 'Save Changes',
                        onPressed: _isSaving ? null : _saveProfile,
                        isLoading: _isSaving,
                        semanticLabel: 'Save operator profile changes',
                      ),
                      const SizedBox(height: 12),
                      AppActionButton(
                        label: 'Cancel',
                        outlined: true,
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setState(() => _isEditing = false);
                                await _loadProfile();
                              },
                        semanticLabel: 'Cancel operator profile edit',
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
