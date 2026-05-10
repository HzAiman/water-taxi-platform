import 'package:flutter/material.dart';

class PassengerBrand {
  const PassengerBrand._();

  static const Color mint = Color(0xFF0EC096);
  static const Color blue = Color(0xFF0F4C75);
  static const Color surface = Color(0xFFF5FBFA);
  static const Color softMint = Color(0xFFE9FAF5);
  static const Color border = Color(0xFFD8E8EA);
  static const Color ink = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF666666);

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, blue],
  );
}
