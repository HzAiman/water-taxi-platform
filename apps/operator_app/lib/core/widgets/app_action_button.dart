import 'package:flutter/material.dart';

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

  static const Color _brandOrange = Color(0xFFFF7A00);
  static const Color _brandMagenta = Color(0xFFCA4B8C);

  @override
  Widget build(BuildContext context) {
    final effectiveForeground = foregroundColor ?? Colors.white;
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: outlined ? foregroundColor : effectiveForeground,
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
              foregroundColor: foregroundColor ?? _brandMagenta,
              side: BorderSide(color: borderColor ?? _brandMagenta, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: child,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              gradient: onPressed == null || isLoading
                  ? null
                  : const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [_brandOrange, _brandMagenta],
                    ),
              color: onPressed == null || isLoading
                  ? Colors.grey.shade300
                  : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: onPressed == null || isLoading
                  ? null
                  : [
                      BoxShadow(
                        color: _brandMagenta.withValues(alpha: 0.24),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
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
