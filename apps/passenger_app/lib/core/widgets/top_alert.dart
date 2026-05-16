import 'dart:async';

import 'package:flutter/material.dart';
import 'package:passenger_app/core/theme/passenger_brand.dart';

void showTopAlert(
  BuildContext context, {
  required String message,
  String? title,
  Color iconColor = PassengerBrand.blue,
  IconData icon = Icons.info_outline,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final displayMessage = _calmAlertMessage(message);
  final overlayState = Overlay.of(context, rootOverlay: true);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      return _TopAlertOverlay(
        message: displayMessage,
        title: title,
        iconColor: iconColor,
        icon: icon,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onClosed: () => entry.remove(),
      );
    },
  );

  overlayState.insert(entry);
}

String _calmAlertMessage(String message) {
  final trimmed = message.trim();
  final text = trimmed.toLowerCase();

  if (text.contains('too-many-requests') ||
      text.contains('blocked all requests') ||
      text.contains('unusual activity')) {
    return 'Too many attempts. Please wait before trying again.';
  }

  if (text.contains('permission-denied') ||
      text.contains('permission denied') ||
      text.contains('insufficient permissions')) {
    return 'You no longer have permission to perform this action. Refresh, then sign in again if needed.';
  }

  if (text.contains('firebase_auth') ||
      text.contains('cloud_firestore') ||
      text.contains('firebaseexception') ||
      text.contains('platformexception')) {
    return 'The app could not complete this action right now. Please try again.';
  }

  return trimmed;
}

void showTopError(
  BuildContext context, {
  required String message,
  String title = 'Something went wrong',
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  showTopAlert(
    context,
    message: message,
    title: title,
    iconColor: Colors.red,
    icon: Icons.error_outline,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

void showTopSuccess(
  BuildContext context, {
  required String message,
  String title = 'Success',
  Duration duration = const Duration(seconds: 4),
}) {
  showTopAlert(
    context,
    message: message,
    title: title,
    iconColor: PassengerBrand.blue,
    icon: Icons.verified_rounded,
    duration: duration,
  );
}

void showTopInfo(
  BuildContext context, {
  required String message,
  String title = 'Notice',
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  showTopAlert(
    context,
    message: message,
    title: title,
    iconColor: PassengerBrand.blue,
    icon: Icons.info_outline,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

class _TopAlertOverlay extends StatefulWidget {
  const _TopAlertOverlay({
    required this.message,
    required this.title,
    required this.iconColor,
    required this.icon,
    required this.duration,
    required this.onClosed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final Color iconColor;
  final IconData icon;
  final Duration duration;
  final VoidCallback onClosed;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_TopAlertOverlay> createState() => _TopAlertOverlayState();
}

class _TopAlertOverlayState extends State<_TopAlertOverlay> {
  bool _visible = false;
  bool _isClosing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = true;
      });
    });

    _timer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (_isClosing || !mounted) {
      return;
    }

    _isClosing = true;
    setState(() {
      _visible = false;
    });

    Future.delayed(const Duration(milliseconds: 220), widget.onClosed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topInset + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _visible ? Offset.zero : const Offset(0, -1.1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _visible ? 1 : 0,
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.up,
              onDismissed: (_) => _dismiss(),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: widget.iconColor == PassengerBrand.blue
                            ? PassengerBrand.gradient
                            : null,
                        color: widget.iconColor == PassengerBrand.blue
                            ? null
                            : widget.iconColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.iconColor == PassengerBrand.blue
                            ? Colors.white
                            : widget.iconColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.title != null) ...[
                            Text(
                              widget.title!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            widget.message,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF666666),
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () {
                                widget.onAction!.call();
                                _dismiss();
                              },
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: widget.iconColor,
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
