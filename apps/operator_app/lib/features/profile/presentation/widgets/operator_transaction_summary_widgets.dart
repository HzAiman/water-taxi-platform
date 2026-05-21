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
    final fare = booking.totalFare;
    final updated = booking.updatedAt ?? booking.createdAt;
    final passengerName = booking.userName.trim().isEmpty
        ? 'Passenger'
        : booking.userName.trim();
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
                child: Text(
                  route,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                size: 17,
                color: OperatorBrand.magenta,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  passengerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5B73),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CountPill(
                icon: Icons.groups_rounded,
                label: 'Total',
                value: booking.passengerCount.toString(),
              ),
              _CountPill(
                icon: Icons.person_outline_rounded,
                label: 'Adults',
                value: booking.adultCount.toString(),
              ),
              _CountPill(
                icon: Icons.child_care_rounded,
                label: 'Children',
                value: booking.childCount.toString(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _HistoryMetaLine(
                  icon: Icons.payments_rounded,
                  text: 'RM ${fare.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HistoryMetaLine(
                  icon: Icons.update_rounded,
                  text: _fmt(updated),
                ),
              ),
            ],
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
    return '$origin -> $destination';
  }

  static String _statusLabel(BookingStatus status) {
    final raw = status.firestoreValue.replaceAll('_', ' ');
    return raw
        .split(' ')
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

class _HistoryMetaLine extends StatelessWidget {
  const _HistoryMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4B5B73),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class StatementTile extends StatelessWidget {
  const StatementTile({
    super.key,
    required this.record,
    required this.onShare,
    required this.onDelete,
  });

  final StatementRecord record;
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
                  onPressed: () => unawaited(onShare()),
                  icon: const Icon(
                    Icons.share_outlined,
                    color: OperatorBrand.magenta,
                  ),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onDelete()),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: OperatorBrand.magenta,
                  ),
                  label: const Text('Delete'),
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
