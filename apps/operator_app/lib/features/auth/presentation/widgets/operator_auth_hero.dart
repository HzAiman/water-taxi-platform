import 'package:flutter/material.dart';
import 'package:operator_app/core/theme/operator_brand.dart';

class OperatorAuthHero extends StatelessWidget {
  const OperatorAuthHero({super.key, required this.icon, this.size = 120});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              OperatorBrand.orange.withValues(alpha: 0.14),
              OperatorBrand.magenta.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: Icon(icon, size: size * 0.58, color: OperatorBrand.magenta),
      ),
    );
  }
}
