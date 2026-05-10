import 'package:flutter/material.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';

class AppActionButton extends StatelessWidget {
  const AppActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.outlined = false,
    this.semanticLabel,
    this.foregroundColor,
    this.borderColor,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  final String? semanticLabel;
  final Color? foregroundColor;
  final Color? borderColor;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: foregroundColor,
      ),
    );

    final loading = const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );

    final child = icon == null
        ? (isLoading ? loading : text)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon!,
              const SizedBox(width: 8),
              isLoading ? loading : text,
            ],
          );

    final button = outlined
        ? OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: foregroundColor ?? PassengerBrand.blue,
              side: BorderSide(
                color: borderColor ?? PassengerBrand.blue,
                width: 1.5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: child,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: onPressed == null || isLoading
                  ? null
                  : PassengerBrand.gradient,
              color: onPressed == null || isLoading
                  ? Colors.grey.shade300
                  : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: onPressed == null || isLoading
                  ? null
                  : [
                      BoxShadow(
                        color: PassengerBrand.blue.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: child,
            ),
          );

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}
