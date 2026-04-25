import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/auth/presentation/widgets/operator_profile_setup_form.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:provider/provider.dart';

class OperatorProfileSetupPage extends StatefulWidget {
  const OperatorProfileSetupPage({
    super.key,
    required this.uid,
    required this.email,
  });

  final String uid;
  final String email;

  @override
  State<OperatorProfileSetupPage> createState() =>
      _OperatorProfileSetupPageState();
}

class _OperatorProfileSetupPageState extends State<OperatorProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final operatorRepo = context.read<OperatorRepository>();
      await operatorRepo.saveProfile(
        uid: widget.uid,
        name: _nameController.text,
        email: widget.email,
        operatorId: _idController.text,
      );
    } catch (e) {
      if (mounted) {
        showTopError(
          context,
          message: 'Failed to save profile: ${e.toString()}',
          title: 'Profile setup failed',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: OperatorProfileSetupForm(
            formKey: _formKey,
            nameController: _nameController,
            idController: _idController,
            email: widget.email,
            isSaving: _isSaving,
            onSubmit: _saveProfile,
          ),
        ),
      ),
    );
  }
}
