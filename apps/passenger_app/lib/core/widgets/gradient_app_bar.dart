import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';

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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: PassengerBrand.gradient),
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
