import 'package:flutter/material.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:operator_app/core/widgets/app_action_button.dart';
import 'package:operator_app/features/auth/presentation/widgets/operator_auth_hero.dart';

class OperatorProfileSetupForm extends StatelessWidget {
  const OperatorProfileSetupForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.idController,
    required this.email,
    required this.isSaving,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController idController;
  final String email;
  final bool isSaving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const OperatorAuthHero(icon: Icons.badge_outlined),
          const SizedBox(height: 32),
          Text(
            'First-time setup',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please provide your operator details to continue.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: nameController,
            enabled: !isSaving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(
                Icons.person_outline,
                color: OperatorBrand.magenta,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: idController,
            enabled: !isSaving,
            decoration: const InputDecoration(
              labelText: 'Operator ID',
              hintText: 'e.g. OP-001',
              prefixIcon: Icon(
                Icons.badge_outlined,
                color: OperatorBrand.magenta,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your operator ID';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            enabled: false,
            initialValue: email,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(
                Icons.email_outlined,
                color: OperatorBrand.magenta,
              ),
            ),
          ),
          const SizedBox(height: 32),
          AppActionButton(
            label: 'Save and Continue',
            onPressed: isSaving ? null : onSubmit,
            isLoading: isSaving,
          ),
        ],
      ),
    );
  }
}
