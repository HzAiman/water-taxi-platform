import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorSummarySectionCard extends StatelessWidget {
  const OperatorSummarySectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  static const Color _brandOrange = OperatorBrand.orange;
  static const Color _brandMagenta = OperatorBrand.magenta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_brandOrange, _brandMagenta],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class OperatorSummaryMetricChip extends StatelessWidget {
  const OperatorSummaryMetricChip({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  static const Color _brandOrange = OperatorBrand.orange;
  static const Color _brandMagenta = OperatorBrand.magenta;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _brandOrange.withValues(alpha: 0.12),
            _brandMagenta.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brandMagenta.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _brandMagenta,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4B5B73),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class OperatorSummaryInfoRow extends StatelessWidget {
  const OperatorSummaryInfoRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5B73),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class RideHistoryTile extends StatelessWidget {
  const RideHistoryTile({super.key, required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    final created = booking.createdAt;
    final passengerName = booking.userName.trim().isEmpty
        ? 'Passenger'
        : booking.userName.trim();
    final phone = booking.userPhone.trim().isEmpty
        ? 'No phone number'
        : booking.userPhone.trim();
    final paymentMethod = PaymentMethods.label(booking.paymentMethod);
    final paymentStatus = _rawStatusLabel(booking.paymentStatus);
    final route = _routeLabel(booking);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AutoScrollingText(
                  text: route,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(booking.status).withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(booking.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _statusColor(booking.status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HistoryDetailLine(
            icon: Icons.person_rounded,
            label: 'Passenger',
            value: passengerName,
          ),
          const SizedBox(height: 8),
          _HistoryDetailLine(
            icon: Icons.phone_rounded,
            label: 'Phone',
            value: phone,
          ),
          const SizedBox(height: 9),
          _PassengerCountGroup(booking: booking),
          const SizedBox(height: 10),
          _HistoryDetailLine(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Payment',
            value: '$paymentMethod • $paymentStatus',
          ),
          const SizedBox(height: 8),
          _HistoryDetailLine(
            icon: Icons.schedule_rounded,
            label: 'Booked',
            value: _fmt(created),
          ),
        ],
      ),
    );
  }

  static String _routeLabel(BookingModel booking) {
    final origin = booking.origin.trim().isEmpty ? 'Pickup' : booking.origin;
    final destination = booking.destination.trim().isEmpty
        ? 'Dropoff'
        : booking.destination;
    return '$origin → $destination';
  }

  static String _statusLabel(BookingStatus status) {
    final raw = status.firestoreValue.replaceAll('_', ' ');
    return _rawStatusLabel(raw);
  }

  static String _rawStatusLabel(String raw) {
    return raw
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Color _statusColor(BookingStatus status) {
    return switch (status) {
      BookingStatus.completed => OperatorBrand.goOnlineGreen,
      BookingStatus.cancelled => const Color(0xFFB42318),
      BookingStatus.rejected => const Color(0xFFB42318),
      BookingStatus.pending => OperatorBrand.orange,
      BookingStatus.accepted || BookingStatus.onTheWay => OperatorBrand.magenta,
      BookingStatus.unknown => const Color(0xFF64748B),
    };
  }

  static String _fmt(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _PassengerCountGroup extends StatelessWidget {
  const _PassengerCountGroup({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: OperatorBrand.magenta.withValues(alpha: 0.12),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _CountPill(
              icon: Icons.groups_rounded,
              label: 'Total',
              value: booking.passengerCount.toString(),
            ),
            const SizedBox(width: 6),
            _CountPill(
              icon: Icons.person_outline_rounded,
              label: 'Adults',
              value: booking.adultCount.toString(),
            ),
            const SizedBox(width: 6),
            _CountPill(
              icon: Icons.child_care_rounded,
              label: 'Children',
              value: booking.childCount.toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: OperatorBrand.magenta),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF4B5B73),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDetailLine extends StatelessWidget {
  const _HistoryDetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF64748B),
      fontWeight: FontWeight.w800,
    );
    const valueStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF1A1A1A),
      fontWeight: FontWeight.w800,
    );

    return Row(
      children: [
        Icon(icon, size: 16, color: OperatorBrand.magenta),
        const SizedBox(width: 7),
        Text('$label: ', style: labelStyle),
        Expanded(
          child: _AutoScrollingText(text: value, style: valueStyle),
        ),
      ],
    );
  }
}

class _AutoScrollingText extends StatefulWidget {
  const _AutoScrollingText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  static const Duration _pause = Duration(milliseconds: 900);

  @override
  State<_AutoScrollingText> createState() => _AutoScrollingTextState();
}

class _AutoScrollingTextState extends State<_AutoScrollingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _scrollDistance = 0;
  Duration? _duration;
  bool _loopScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _AutoScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _duration = null;
      _loopScheduled = false;
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        final maxWidth = constraints.maxWidth;
        final textWidth = textPainter.width;

        if (!maxWidth.isFinite || textWidth <= maxWidth) {
          _controller.stop();
          _controller.value = 0;
          _duration = null;
          _loopScheduled = false;
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          );
        }

        final distance = textWidth - maxWidth + 24;
        final duration = Duration(
          milliseconds: (distance * 42).clamp(2600, 9000).round(),
        );
        _configureScrolling(distance: distance, duration: duration);

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(-_scrollDistance * _controller.value, 0),
                child: child,
              );
            },
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
  }

  void _configureScrolling({
    required double distance,
    required Duration duration,
  }) {
    _scrollDistance = distance;
    if (_duration == duration && _loopScheduled) {
      return;
    }
    _duration = duration;
    _loopScheduled = true;
    _controller.duration = duration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _duration != duration) {
        _loopScheduled = false;
        return;
      }
      while (mounted && _duration == duration) {
        await Future<void>.delayed(_AutoScrollingText._pause);
        if (!mounted || _duration != duration) {
          return;
        }
        await _controller.forward(from: 0);
      }
      _loopScheduled = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class StatementTile extends StatelessWidget {
  const StatementTile({
    super.key,
    required this.record,
    required this.onView,
    required this.onShare,
    required this.onDelete,
  });

  final StatementRecord record;
  final Future<void> Function() onView;
  final Future<void> Function() onShare;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final generated = _fmt(record.generatedAt);
    final period = record.periodStart != null && record.periodEnd != null
        ? '${record.period.label} - ${_fmtDate(record.periodStart!)} - ${_fmtDate(record.periodEnd!)}'
        : record.period.label;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.fileName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Period: $period'),
          Text('Generated: $generated'),
          Text('Completed rides: ${record.completedRides}'),
          Text('Earnings: RM ${record.totalEarnings.toStringAsFixed(2)}'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onView()),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    color: OperatorBrand.magenta,
                    size: 16,
                  ),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onShare()),
                  icon: const Icon(
                    Icons.share_outlined,
                    color: OperatorBrand.magenta,
                    size: 16,
                  ),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onDelete()),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: OperatorBrand.magenta,
                    size: 16,
                  ),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  static String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
