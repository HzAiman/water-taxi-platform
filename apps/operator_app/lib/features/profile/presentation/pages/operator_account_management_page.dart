import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_account_form.dart';
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
          OperatorAccountForm(
            formKey: _formKey,
            nameController: _nameController,
            idController: _idController,
            emailController: _emailController,
            isEditing: _isEditing,
            isSaving: _isSaving,
            onEdit: () {
              setState(() => _isEditing = true);
            },
            onSave: _saveProfile,
            onCancel: () async {
              setState(() => _isEditing = false);
              await _loadProfile();
            },
          ),
        ],
      ),
    );
  }
}
