import 'package:flutter/material.dart';
import 'package:operator_app/core/theme/operator_brand.dart';

class OperatorProfileHeader extends StatelessWidget {
  const OperatorProfileHeader({
    super.key,
    required this.name,
    required this.email,
    required this.operatorId,
    required this.phoneNumber,
    required this.topInset,
  });

  final String name;
  final String email;
  final String operatorId;
  final String phoneNumber;
  final double topInset;

  static const Color _brandOrange = OperatorBrand.orange;
  static const Color _brandMagenta = OperatorBrand.magenta;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, topInset + 24, 24, 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_brandOrange, _brandMagenta],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              email,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              operatorId,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              phoneNumber,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
