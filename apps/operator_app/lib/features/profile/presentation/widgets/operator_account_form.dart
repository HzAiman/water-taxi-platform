import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/app_action_button.dart';

class OperatorAccountForm extends StatelessWidget {
  const OperatorAccountForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.idController,
    required this.emailController,
    required this.isEditing,
    required this.isSaving,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController idController;
  final TextEditingController emailController;
  final bool isEditing;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
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
            controller: nameController,
            enabled: isEditing,
            decoration: const InputDecoration(
              hintText: 'Enter your full name',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (isEditing && (value == null || value.trim().isEmpty)) {
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
            controller: idController,
            enabled: isEditing,
            decoration: const InputDecoration(
              hintText: 'Enter your operator ID',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (value) {
              if (isEditing && (value == null || value.trim().isEmpty)) {
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
            controller: emailController,
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
          if (!isEditing)
            AppActionButton(
              label: 'Edit Profile',
              onPressed: onEdit,
              semanticLabel: 'Edit operator profile',
            )
          else
            Column(
              children: [
                AppActionButton(
                  label: 'Save Changes',
                  onPressed: isSaving ? null : onSave,
                  isLoading: isSaving,
                  semanticLabel: 'Save operator profile changes',
                ),
                const SizedBox(height: 12),
                AppActionButton(
                  label: 'Cancel',
                  outlined: true,
                  onPressed: isSaving ? null : () => onCancel(),
                  semanticLabel: 'Cancel operator profile edit',
                ),
              ],
            ),
        ],
      ),
    );
  }
}
