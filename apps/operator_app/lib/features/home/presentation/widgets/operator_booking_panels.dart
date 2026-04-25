import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_app/features/home/presentation/viewmodels/operator_home_view_model.dart';
import 'package:operator_app/features/home/presentation/widgets/operator_info_card.dart';
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
  });

  final BookingModel booking;
  final bool isUpdating;
  final String detailText;
  final Future<void> Function() onStartTrip;
  final Future<void> Function() onRelease;

  @override
  Widget build(BuildContext context) {
    final status = booking.status;
    final isAccepted = status == BookingStatus.accepted;
    final isOnTheWay = status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted ? const Color(0xFF0066CC) : Colors.green;

    var subtitle = detailText;
    if (isStale) {
      subtitle =
          '$subtitle\n\nThis accepted booking looks stale. Start the trip or release it back to the queue.';
    }

    return OperatorInfoCard(
      icon: isAccepted ? Icons.directions_boat : Icons.route,
      iconColor: actionColor,
      title: 'Current Booking: ${formatStatusLabel(status.firestoreValue)}',
      subtitle: subtitle,
      actionLabel: isAccepted ? 'Start Trip' : null,
      actionColor: actionColor,
      secondaryActionLabel: isAccepted ? 'Release' : null,
      secondaryActionColor: const Color(0xFFFFF1F1),
      secondaryActionTextColor: const Color(0xFFB42318),
      showActionLoading: isUpdating,
      onAction: isUpdating || isOnTheWay
          ? null
          : () async {
              await onStartTrip();
            },
      onSecondaryAction: isUpdating || !isAccepted
          ? null
          : () async {
              await onRelease();
            },
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
    return OperatorInfoCard(
      icon: Icons.notifications_active,
      iconColor: Colors.orange,
      title: pendingCount > 1
          ? 'Next Pending Booking ($pendingCount in queue)'
          : 'Next Pending Booking',
      subtitle: detailText,
      actionLabel: 'Accept Booking',
      actionColor: const Color(0xFF0066CC),
      secondaryActionLabel: 'Reject',
      secondaryActionColor: Colors.orange.shade50,
      secondaryActionTextColor: Colors.orange.shade900,
      showActionLoading: isUpdating,
      onAction: isUpdating
          ? null
          : () async {
              await onAccept();
            },
      onSecondaryAction: isUpdating
          ? null
          : () async {
              await onReject();
            },
    );
  }
}

class OperatorCollapsibleNavigationCard extends StatefulWidget {
  const OperatorCollapsibleNavigationCard({
    super.key,
    required this.progressLabel,
    required this.remaining,
    required this.eta,
    required this.nextMarkerText,
    required this.offRouteText,
    required this.isUpdating,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
  });

  final String progressLabel;
  final String remaining;
  final String eta;
  final String nextMarkerText;
  final String? offRouteText;
  final bool isUpdating;
  final String primaryActionLabel;
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
            '${widget.remaining}  •  ETA ${widget.eta}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildNavigationMetric('Remaining', widget.remaining),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildNavigationMetric('ETA', widget.eta)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.nextMarkerText,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.offRouteText != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.offRouteText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A3412),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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

  Widget _buildNavigationMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
