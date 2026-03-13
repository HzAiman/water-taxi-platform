import 'dart:async';

import 'package:flutter/material.dart';

void showTopAlert(
  BuildContext context, {
  required String message,
  Color color = const Color(0xFF0066CC),
  IconData icon = Icons.info_outline,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlayState = Overlay.of(context, rootOverlay: true);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      return _TopAlertOverlay(
        message: message,
        color: color,
        icon: icon,
        duration: duration,
        onClosed: () => entry.remove(),
      );
    },
  );

  overlayState.insert(entry);
}

void showTopError(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  showTopAlert(
    context,
    message: message,
    color: Colors.red,
    icon: Icons.error,
    duration: duration,
  );
}

void showTopSuccess(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  showTopAlert(
    context,
    message: message,
    color: const Color(0xFF0066CC),
    icon: Icons.check_circle,
    duration: duration,
  );
}

void showTopInfo(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  showTopAlert(
    context,
    message: message,
    color: const Color(0xFF0066CC),
    icon: Icons.info_outline,
    duration: duration,
  );
}

class _TopAlertOverlay extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final Duration duration;
  final VoidCallback onClosed;

  const _TopAlertOverlay({
    required this.message,
    required this.color,
    required this.icon,
    required this.duration,
    required this.onClosed,
  });

  @override
  State<_TopAlertOverlay> createState() => _TopAlertOverlayState();
}

class _TopAlertOverlayState extends State<_TopAlertOverlay> {
  bool _visible = false;
  Timer? _timer;
  bool _isClosing = false;

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

    Future.delayed(const Duration(milliseconds: 220), () {
      widget.onClosed();
    });
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
          offset: _visible ? Offset.zero : const Offset(0, -1.15),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _visible ? 1 : 0,
            child: Dismissible(
              key: UniqueKey(),
              direction: DismissDirection.up,
              onDismissed: (_) => _dismiss(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.color.withValues(alpha: 0.45)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 70,
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          bottomLeft: Radius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(widget.icon, color: widget.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close, size: 18),
                      color: const Color(0xFF666666),
                      tooltip: 'Dismiss',
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
