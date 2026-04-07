import 'dart:async';

import 'package:flutter/material.dart';

class OperatorInfoCard extends StatelessWidget {
  const OperatorInfoCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.secondaryActionLabel,
    this.actionColor = const Color(0xFF0066CC),
    this.secondaryActionColor = const Color(0xFFF3F4F6),
    this.secondaryActionTextColor = const Color(0xFF1F2937),
    this.showActionLoading = false,
    this.onAction,
    this.onSecondaryAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final String? secondaryActionLabel;
  final Color actionColor;
  final Color secondaryActionColor;
  final Color secondaryActionTextColor;
  final bool showActionLoading;
  final Future<void> Function()? onAction;
  final Future<void> Function()? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (secondaryActionLabel != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondaryAction == null
                          ? null
                          : () => unawaited(onSecondaryAction!()),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: secondaryActionColor,
                        foregroundColor: secondaryActionTextColor,
                        side: BorderSide(
                          color: secondaryActionTextColor.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Text(secondaryActionLabel!),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAction == null
                        ? null
                        : () => unawaited(onAction!()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: Colors.white,
                    ),
                    child: showActionLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(actionLabel!),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
