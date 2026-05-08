import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GradientAppBar({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle = true,
  });

  final String title;
  final List<Widget>? actions;
  final bool centerTitle;

  static const Color _brandOrange = Color(0xFFFF7A00);
  static const Color _brandMagenta = Color(0xFFCA4B8C);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandOrange, _brandMagenta],
        ),
      ),
      child: AppBar(
        title: Text(title),
        centerTitle: centerTitle,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: actions,
      ),
    );
  }
}
