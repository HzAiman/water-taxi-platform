import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_app/core/theme/operator_brand.dart';
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
    required this.onRefresh,
    required this.isRefreshing,
  });

  final int pendingCount;
  final int activeCount;
  final bool isQueueExpanded;
  final bool isActiveExpanded;
  final VoidCallback onPendingTap;
  final VoidCallback onActiveTap;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
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
          Container(width: 1, height: 30, color: Colors.grey[300]),
          Expanded(
            child: OperatorStatTile(
              label: 'Active Trip',
              value: activeCount.toString(),
              color: OperatorBrand.magenta,
              isExpanded: isActiveExpanded,
              onTap: onActiveTap,
            ),
          ),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          const SizedBox(width: 4),
          Tooltip(
            message: isRefreshing ? 'Refreshing bookings' : 'Refresh bookings',
            child: SizedBox(
              width: 34,
              height: 34,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: isRefreshing ? null : onRefresh,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: isRefreshing
                      ? const SizedBox(
                          key: ValueKey('booking-refresh-progress'),
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          key: ValueKey('booking-refresh-icon'),
                          size: 21,
                        ),
                ),
                color: OperatorBrand.magenta,
                disabledColor: Colors.grey[500],
              ),
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
    this.poolBookings = const <BookingModel>[],
    required this.onStartTrip,
    required this.onRelease,
    required this.onCallCustomer,
  });

  final BookingModel booking;
  final bool isUpdating;
  final String detailText;
  final List<BookingModel> poolBookings;
  final Future<void> Function() onStartTrip;
  final Future<void> Function() onRelease;
  final Future<void> Function() onCallCustomer;

  @override
  Widget build(BuildContext context) {
    final status = booking.status;
    final isAccepted = status == BookingStatus.accepted;
    final isOnTheWay = status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted
        ? OperatorBrand.magenta
        : OperatorBrand.goOnlineGreen;

    final passengerSummary = booking.passengerCount == 1
        ? '1 passenger'
        : '${booking.passengerCount} passengers';
    final fareSummary = booking.totalFare > 0
        ? formatCurrency(booking.totalFare)
        : 'Fare N/A';
    final currentStop = booking.currentPoolStop;
    final nextStop = currentStop == null
        ? null
        : _nextStopAfter(booking.poolStopPlan, currentStop);
    var subtitle = currentStop != null
        ? _poolStopSubtitle(currentStop, poolBookings)
        : isOnTheWay
        ? '${booking.origin} → ${booking.destination}\n$passengerSummary - $fareSummary'
        : detailText;
    if (isStale) {
      subtitle =
          '$subtitle\n\nThis accepted booking looks stale. Start the trip or release it back to the queue.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                size: currentStop != null ? 22 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currentStop != null
                      ? 'Next Stop'
                      : booking.userName.trim().isEmpty
                      ? 'Current Trip'
                      : booking.userName,
                  style: TextStyle(
                    fontSize: currentStop != null ? 16 : 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[850],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  currentStop != null
                      ? _routeDirectionLabel(booking.routeDirection)
                      : formatStatusLabel(status.firestoreValue),
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
          currentStop != null
              ? _buildCurrentStopSummary(currentStop, nextStop)
              : Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: isStale ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
          if (currentStop != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPoolChip(
                  _poolPhaseLabel(booking),
                  OperatorBrand.magenta,
                  Icons.groups_2,
                ),
                _buildPoolChip(
                  _stopOccupancyLabel(currentStop, poolBookings),
                  Colors.blueGrey,
                  Icons.alt_route,
                ),
              ],
            ),
            if (booking.poolStopPlan.length > 1) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'View route order',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: OperatorBrand.magenta,
                  ),
                ),
                children: [_buildRouteOrder(booking.poolStopPlan, currentStop)],
              ),
            ],
          ],
          const SizedBox(height: 10),
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
                    foregroundColor: OperatorBrand.magenta,
                    side: BorderSide(
                      color: OperatorBrand.magenta.withValues(alpha: 0.20),
                    ),
                    padding: EdgeInsets.symmetric(
                      vertical: currentStop != null ? 11 : 8,
                    ),
                    textStyle: TextStyle(
                      fontSize: currentStop != null ? 13 : 12,
                    ),
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
                      padding: EdgeInsets.symmetric(
                        vertical: currentStop != null ? 11 : 8,
                      ),
                      textStyle: TextStyle(
                        fontSize: currentStop != null ? 13 : 12,
                      ),
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
                      padding: EdgeInsets.symmetric(
                        vertical: currentStop != null ? 11 : 8,
                      ),
                      textStyle: TextStyle(
                        fontSize: currentStop != null ? 13 : 12,
                      ),
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
                        : Text(
                            booking.poolGroupId == null
                                ? 'Start'
                                : 'Start Route',
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStopSummary(
    PoolStopPlanItem currentStop,
    PoolStopPlanItem? nextStop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _stopActionLabel(currentStop, poolBookings),
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey[900],
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          _stopDisplayName(currentStop),
          style: const TextStyle(
            fontSize: 16,
            color: OperatorBrand.magenta,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (nextStop != null) ...[
          const SizedBox(height: 7),
          _buildNextStopPreview(nextStop),
        ],
      ],
    );
  }

  Widget _buildNextStopPreview(PoolStopPlanItem nextStop) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            nextStop.isPickup ? Icons.login : Icons.logout,
            size: 15,
            color: Colors.blueGrey,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Next: ${_stopActionLabel(nextStop, poolBookings)} - ${_stopDisplayName(nextStop)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteOrder(
    List<PoolStopPlanItem> stops,
    PoolStopPlanItem currentStop,
  ) {
    final visibleStops = stops.take(4).toList(growable: false);
    final hiddenCount = stops.length - visibleStops.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Route Order',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final stop in visibleStops)
            _buildRouteOrderRow(stop, currentStop),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 22),
              child: Text(
                '+ $hiddenCount more stop${hiddenCount == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteOrderRow(
    PoolStopPlanItem stop,
    PoolStopPlanItem currentStop,
  ) {
    final isCurrent = stop.stopId == currentStop.stopId;
    final isCompleted = stop.status == 'completed';
    final color = isCurrent
        ? OperatorBrand.magenta
        : isCompleted
        ? OperatorBrand.goOnlineGreen
        : Colors.blueGrey;
    final icon = isCompleted
        ? Icons.check_circle
        : isCurrent
        ? Icons.navigation
        : stop.isPickup
        ? Icons.login
        : Icons.logout;

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stopActionLabel(stop, poolBookings),
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrent ? OperatorBrand.magenta : Colors.grey[850],
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _stopDisplayName(stop),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _poolStopSubtitle(
  PoolStopPlanItem stop,
  List<BookingModel> poolBookings,
) {
  return '${_stopActionLabel(stop, poolBookings)}\n${_stopDisplayName(stop)}';
}

String _stopDisplayName(PoolStopPlanItem stop) {
  final stopName = stop.stopName.trim();
  if (stopName.isNotEmpty) {
    return stopName;
  }
  final stopJettyId = stop.stopJettyId?.trim();
  if (stopJettyId != null && stopJettyId.isNotEmpty) {
    return stopJettyId;
  }
  return stop.isPickup ? 'Pickup stop' : 'Dropoff stop';
}

String _stopActionLabel(
  PoolStopPlanItem stop,
  List<BookingModel> poolBookings,
) {
  final verb = stop.isPickup ? 'Pick up' : 'Drop off';
  final passengerCount = _stopPassengerCount(stop, poolBookings);
  final noun = passengerCount == 1 ? 'passenger' : 'passengers';
  return '$verb $passengerCount $noun';
}

String _stopOccupancyLabel(
  PoolStopPlanItem stop,
  List<BookingModel> poolBookings,
) {
  final passengerCount = _stopPassengerCount(stop, poolBookings);
  final noun = passengerCount == 1 ? 'passenger' : 'passengers';
  return '$passengerCount $noun at stop';
}

int _stopPassengerCount(
  PoolStopPlanItem stop,
  List<BookingModel> poolBookings,
) {
  final stopBookingIds = stop.bookingIds.toSet();
  final count = poolBookings
      .where((booking) => stopBookingIds.contains(booking.bookingId))
      .fold<int>(0, (sum, booking) => sum + booking.passengerCount);
  if (count > 0) {
    return count;
  }
  return stop.bookingIds.isEmpty ? 1 : stop.bookingIds.length;
}

PoolStopPlanItem? _nextStopAfter(
  List<PoolStopPlanItem> stops,
  PoolStopPlanItem currentStop,
) {
  final currentIndex = stops.indexWhere(
    (stop) => stop.stopId == currentStop.stopId,
  );
  if (currentIndex < 0) {
    return null;
  }
  for (var i = currentIndex + 1; i < stops.length; i++) {
    final stop = stops[i];
    if (stop.status != 'completed' && stop.status != 'skipped') {
      return stop;
    }
  }
  return null;
}

String _routeDirectionLabel(String? routeDirection) {
  final normalized = routeDirection?.trim().toLowerCase();
  if (normalized == 'reverse') {
    return 'Reverse route';
  }
  if (normalized == 'forward') {
    return 'Forward route';
  }
  return 'Pool route';
}

String _poolPhaseLabel(BookingModel booking) {
  final phase = booking.poolPhase?.trim().toLowerCase();
  if (phase == 'onboard' || booking.onboard) {
    return 'Onboard';
  }
  if (phase == 'dropped_off' || booking.status == BookingStatus.completed) {
    return 'Dropped off';
  }
  if (phase == 'cancelled' || booking.status == BookingStatus.cancelled) {
    return 'Cancelled';
  }
  return 'Waiting pickup';
}

Widget _buildPoolChip(String label, Color color, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[850],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
              fontSize: 12,
              color: Colors.grey[700],
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
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
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isUpdating ? null : () => unawaited(onAccept()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OperatorBrand.magenta,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12),
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
    this.stopLabel,
    this.routeDirectionLabel,
    required this.isUpdating,
    required this.primaryActionLabel,
    required this.routeWarningText,
    required this.onPrimaryAction,
  });

  final String progressLabel;
  final String remaining;
  final String eta;
  final String? stopLabel;
  final String? routeDirectionLabel;
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
  bool _isSubmittingPrimaryAction = false;

  bool get _isPrimaryActionBusy =>
      widget.isUpdating || _isSubmittingPrimaryAction;

  Future<void> _handlePrimaryAction() async {
    if (_isPrimaryActionBusy) {
      return;
    }
    setState(() => _isSubmittingPrimaryAction = true);
    try {
      await widget.onPrimaryAction();
    } finally {
      if (mounted) {
        setState(() => _isSubmittingPrimaryAction = false);
      }
    }
  }

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
                    color: OperatorBrand.magenta,
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
                      color: OperatorBrand.magenta,
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
          if (widget.stopLabel != null ||
              widget.routeDirectionLabel != null) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (widget.stopLabel != null)
                  _buildNavigationChip(
                    widget.stopLabel!,
                    OperatorBrand.magenta,
                    Icons.place,
                  ),
                if (widget.routeDirectionLabel != null)
                  _buildNavigationChip(
                    widget.routeDirectionLabel!,
                    Colors.blueGrey,
                    Icons.swap_vert,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
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
                onPressed: _isPrimaryActionBusy
                    ? null
                    : () => unawaited(_handlePrimaryAction()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _isPrimaryActionBusy
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

  Widget _buildNavigationChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
