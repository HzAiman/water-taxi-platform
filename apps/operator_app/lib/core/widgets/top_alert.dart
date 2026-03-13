import 'dart:async';

import 'package:flutter/material.dart';

void showTopAlert(
  BuildContext context, {
  required String message,
  String? title,
  Color iconColor = const Color(0xFF0066CC),
  IconData icon = Icons.info_outline,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlayState = Overlay.of(context, rootOverlay: true);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      return _TopAlertOverlay(
        message: message,
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
    iconColor: const Color(0xFF0066CC),
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
    iconColor: const Color(0xFF0066CC),
    icon: Icons.info_outline,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

void showTopWelcomeCard(
  BuildContext context, {
  required String operatorLabel,
  Duration duration = const Duration(seconds: 6),
}) {
  showTopAlert(
    context,
    title: 'Welcome back, Operator!',
    message: operatorLabel,
    iconColor: const Color(0xFF0066CC),
    icon: Icons.verified_user,
    duration: duration,
  );
}

void showTopOfflineCard(
  BuildContext context, {
  Duration duration = const Duration(seconds: 4),
}) {
  showTopAlert(
    context,
    title: 'You are now offline',
    message: 'You will not receive new bookings.',
    iconColor: Colors.grey,
    icon: Icons.cloud_off,
    duration: duration,
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
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(widget.icon, color: widget.iconColor, size: 28),
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
                          if (widget.actionLabel != null && widget.onAction != null) ...[
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
                                style: const TextStyle(fontWeight: FontWeight.w700),
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