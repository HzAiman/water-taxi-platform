import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/features/home/presentation/widgets/operator_stat_tile.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorBookingStatsCard extends StatelessWidget {
  const OperatorBookingStatsCard({
    super.key,
    required this.pendingCount,
    required this.activeCount,
    required this.isQueueExpanded,
    required this.isActiveExpanded,
    required this.onPendingTap,
    required this.onActiveTap,
    required this.isRefreshing,
  });

  final int pendingCount;
  final int activeCount;
  final bool isQueueExpanded;
  final bool isActiveExpanded;
  final VoidCallback onPendingTap;
  final VoidCallback onActiveTap;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OperatorStatTile(
              label: 'Pending Queue',
              value: pendingCount.toString(),
              color: Colors.orange,
              isExpanded: isQueueExpanded,
              onTap: onPendingTap,
            ),
          ),
          if (isRefreshing) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: OperatorStatTile(
              label: 'Active Trip',
              value: activeCount.toString(),
              color: const Color(0xFF0066CC),
              isExpanded: isActiveExpanded,
              onTap: onActiveTap,
            ),
          ),
        ],
      ),
    );
  }
}

class OperatorActiveBookingCard extends StatelessWidget {
  const OperatorActiveBookingCard({
    super.key,
    required this.booking,
    required this.isUpdating,
    required this.detailText,
    required this.onStartTrip,
    required this.onRelease,
    required this.onCallCustomer,
  });

  final BookingModel booking;
  final bool isUpdating;
  final String detailText;
  final Future<void> Function() onStartTrip;
  final Future<void> Function() onRelease;
  final Future<void> Function() onCallCustomer;

  @override
  Widget build(BuildContext context) {
    final status = booking.status;
    final isAccepted = status == BookingStatus.accepted;
    final isOnTheWay = status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted ? const Color(0xFF0066CC) : Colors.green;

    final passengerSummary = booking.passengerCount == 1
        ? '1 passenger'
        : '${booking.passengerCount} passengers';
    final fareSummary = booking.totalFare > 0
        ? formatCurrency(booking.totalFare)
        : 'Fare N/A';
    var subtitle = isOnTheWay
        ? '${booking.origin} → ${booking.destination}\n$passengerSummary - $fareSummary'
        : detailText;
    if (isStale) {
      subtitle =
          '$subtitle\n\nThis accepted booking looks stale. Start the trip or release it back to the queue.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAccepted ? Icons.directions_boat : Icons.route,
                color: actionColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  booking.userName.trim().isEmpty
                      ? 'Current Trip'
                      : booking.userName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[850],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  formatStatusLabel(status.firestoreValue),
                  style: TextStyle(
                    fontSize: 11,
                    color: actionColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUpdating
                      ? null
                      : () => unawaited(onCallCustomer()),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0066CC),
                    side: const BorderSide(color: Color(0x330066CC)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (isAccepted) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isUpdating ? null : () => unawaited(onRelease()),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF1F1),
                      foregroundColor: const Color(0xFFB42318),
                      side: const BorderSide(color: Color(0x33B42318)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Release'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isUpdating
                        ? null
                        : () => unawaited(onStartTrip()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: isUpdating
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Start'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class OperatorPendingBookingCard extends StatelessWidget {
  const OperatorPendingBookingCard({
    super.key,
    required this.booking,
    required this.pendingCount,
    required this.isUpdating,
    required this.detailText,
    required this.onAccept,
    required this.onReject,
  });

  final BookingModel booking;
  final int pendingCount;
  final bool isUpdating;
  final String detailText;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final passengerSummary = booking.passengerCount == 1
        ? '1 passenger'
        : '${booking.passengerCount} passengers';
    final fareSummary = booking.totalFare > 0
        ? formatCurrency(booking.totalFare)
        : 'Fare N/A';
    final title = booking.userName.trim().isEmpty
        ? 'Pending Booking'
        : booking.userName.trim();
    final subtitle =
        '${booking.origin} → ${booking.destination}\n$passengerSummary - $fareSummary';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[850],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pendingCount > 1 ? '$pendingCount in queue' : 'Pending',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isUpdating ? null : () => unawaited(onReject()),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.orange.shade50,
                    foregroundColor: Colors.orange.shade900,
                    side: BorderSide(
                      color: Colors.orange.shade900.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isUpdating ? null : () => unawaited(onAccept()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066CC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: isUpdating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Accept Booking'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OperatorCollapsibleNavigationCard extends StatefulWidget {
  const OperatorCollapsibleNavigationCard({
    super.key,
    required this.progressLabel,
    required this.remaining,
    required this.eta,
    required this.isUpdating,
    required this.primaryActionLabel,
    required this.routeWarningText,
    required this.onPrimaryAction,
  });

  final String progressLabel;
  final String remaining;
  final String eta;
  final bool isUpdating;
  final String primaryActionLabel;
  final String? routeWarningText;
  final Future<void> Function() onPrimaryAction;

  @override
  State<OperatorCollapsibleNavigationCard> createState() =>
      _OperatorCollapsibleNavigationCardState();
}

class _OperatorCollapsibleNavigationCardState
    extends State<OperatorCollapsibleNavigationCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.navigation,
                    color: Color(0xFF0066CC),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Navigation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[900],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.progressLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0066CC),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[700],
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.remaining} - ETA ${widget.eta}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.routeWarningText != null) ...[
            const SizedBox(height: 8),
            _buildWarning(widget.routeWarningText!),
          ],
          if (_isExpanded) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isUpdating
                    ? null
                    : () => unawaited(widget.onPrimaryAction()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: widget.isUpdating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        widget.primaryActionLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF9A3412),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
