import 'package:flutter/material.dart';

class OperatorBrand {
  const OperatorBrand._();

  static const Color orange = Color(0xFFFF7A00);
  static const Color magenta = Color(0xFFCA4B8C);
  static const Color surface = Color(0xFFFFF8FB);
  static const Color softOrange = Color(0xFFFFF6EC);
  static const Color softMagenta = Color(0xFFFCEBF4);
  static const Color border = Color(0xFFE8DDE6);
  static const Color ink = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF666666);
  static const Color navigationBlue = Color(0xFF0066CC);
  static const Color goOnlineGreen = Color(0xFF16A34A);

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orange, magenta],
  );
}
