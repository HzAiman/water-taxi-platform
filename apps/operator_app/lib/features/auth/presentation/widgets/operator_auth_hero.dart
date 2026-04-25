import 'package:flutter/material.dart';

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
              const Color(0xFF0066CC).withValues(alpha: 0.1),
              const Color(0xFF0066CC).withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Icon(icon, size: size * 0.58, color: const Color(0xFF0066CC)),
      ),
    );
  }
}
