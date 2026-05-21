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
    required this.onCallPoolCustomer,
  });

  final BookingModel booking;
  final bool isUpdating;
  final String detailText;
  final List<BookingModel> poolBookings;
  final Future<void> Function() onStartTrip;
  final Future<void> Function() onRelease;
  final Future<void> Function() onCallCustomer;
  final Future<void> Function(BookingModel booking) onCallPoolCustomer;

  @override
  Widget build(BuildContext context) {
    final isAccepted = booking.status == BookingStatus.accepted;
    final isNavigating = booking.status == BookingStatus.onTheWay;
    final isStale = isAcceptedBookingStale(booking);
    final actionColor = isAccepted
        ? OperatorBrand.magenta
        : OperatorBrand.goOnlineGreen;

    final currentStop = booking.currentPoolStop ?? _fallbackStopFor(booking);
    final routeStops = booking.poolStopPlan.isNotEmpty
        ? booking.poolStopPlan
        : <PoolStopPlanItem>[currentStop, _fallbackDestinationStopFor(booking)];
    final nextStop = _nextStopAfter(routeStops, currentStop);
    var subtitle = _poolStopSubtitle(currentStop, poolBookings);
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
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isNavigating ? 'Trip Route' : 'Ready To Start',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[850],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _routeDirectionLabel(booking.routeDirection),
                  style: TextStyle(
                    fontSize: 11,
                    color: actionColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (!isNavigating) ...[
            const SizedBox(height: 8),
            _buildCurrentStopSummary(currentStop, nextStop),
          ],
          if (isStale) ...[
            const SizedBox(height: 7),
            Text(
              subtitle.split('\n\n').skip(1).join('\n\n'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade900,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          SizedBox(height: isNavigating ? 6 : 8),
          if (routeStops.length > 1) ...[
            _CompactCollapsibleSection(
              title: 'View route order',
              routeOrder: _buildRouteOrder(routeStops, currentStop),
            ),
          ],
          if (routeStops.length > 1) const SizedBox(height: 4),
          _CompactCollapsibleSection(
            title: 'Active booking list',
            routeOrder: _buildActiveBookingCallList(_callablePoolBookings),
          ),
          if (!isNavigating && poolBookings.length > 1) ...[
            const SizedBox(height: 8),
            _buildPoolBookingList(poolBookings),
          ],
          if (!isNavigating) ...[
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
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                if (isAccepted) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isUpdating
                          ? null
                          : () => unawaited(onRelease()),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF1F1),
                        foregroundColor: const Color(0xFFB42318),
                        side: const BorderSide(color: Color(0x33B42318)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontSize: 13),
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
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontSize: 13),
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
                          : const Text('Start Route'),
                    ),
                  ),
                ],
              ],
            ),
          ],
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
        _AlternatingStopHeadline(
          actionText: _stopHeadlineActionLabel(currentStop, poolBookings),
          stopText: _stopDisplayName(currentStop),
        ),
        if (nextStop != null) ...[
          const SizedBox(height: 8),
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
            child: _LoopingText(
              text:
                  'Next: ${_stopActionLabel(nextStop, poolBookings)} @ ${_stopDisplayName(nextStop)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w700,
              ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      decoration: const BoxDecoration(color: Colors.white),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stops.length; i++)
                _buildRouteOrderRow(
                  stops[i],
                  currentStop,
                  isFirst: i == 0,
                  isLast: i == stops.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteOrderRow(
    PoolStopPlanItem stop,
    PoolStopPlanItem currentStop, {
    required bool isFirst,
    required bool isLast,
  }) {
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

    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isCurrent ? 0.16 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LoopingText(
                    text: _stopActionLabel(stop, poolBookings),
                    style: TextStyle(
                      fontSize: 13,
                      color: isCurrent
                          ? OperatorBrand.magenta
                          : Colors.grey[850],
                      fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _LoopingText(
                    text: _stopDisplayName(stop),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolBookingList(List<BookingModel> bookings) {
    final visibleBookings = bookings.take(3).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: OperatorBrand.magenta.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active pool',
            style: TextStyle(
              fontSize: 11,
              color: OperatorBrand.magenta,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in visibleBookings) _buildPoolBookingRow(item),
        ],
      ),
    );
  }

  Widget _buildPoolBookingRow(BookingModel item) {
    final phase = _poolPhaseLabel(item);
    final route = '${item.origin} -> ${item.destination}';
    final customer = item.userName.trim().isEmpty
        ? 'Passenger'
        : item.userName.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            item.onboard || item.poolPhase == 'onboard'
                ? Icons.directions_boat
                : Icons.schedule,
            size: 14,
            color: item.onboard || item.poolPhase == 'onboard'
                ? OperatorBrand.goOnlineGreen
                : Colors.blueGrey,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _LoopingText(
              text: '$customer - $route',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[850],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            phase,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  List<BookingModel> get _callablePoolBookings {
    if (poolBookings.isNotEmpty) {
      return poolBookings;
    }
    return <BookingModel>[booking];
  }

  Widget _buildActiveBookingCallList(List<BookingModel> bookings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      decoration: const BoxDecoration(color: Colors.white),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 210),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = bookings[index];
            final customer = item.userName.trim().isEmpty
                ? 'Passenger'
                : item.userName.trim();
            final route = '${item.origin} -> ${item.destination}';
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 2, right: 0),
              minLeadingWidth: 28,
              leading: CircleAvatar(
                radius: 13,
                backgroundColor: OperatorBrand.magenta.withValues(alpha: 0.10),
                child: const Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: OperatorBrand.magenta,
                ),
              ),
              title: Text(
                customer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[900],
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                route,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[650],
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: Tooltip(
                message: 'Call $customer',
                child: IconButton.filled(
                  key: ValueKey('active-booking-call-${item.bookingId}'),
                  style: IconButton.styleFrom(
                    backgroundColor: OperatorBrand.magenta,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(34, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => unawaited(onCallPoolCustomer(item)),
                  icon: const Icon(Icons.call_rounded, size: 18),
                ),
              ),
            );
          },
        ),
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

PoolStopPlanItem _fallbackStopFor(BookingModel booking) {
  final isPickedUp =
      booking.onboard ||
      booking.poolPhase == 'onboard' ||
      booking.pickedUpAt != null ||
      booking.passengerPickedUpAt != null;
  return PoolStopPlanItem(
    stopId: isPickedUp ? 'fallback_dropoff' : 'fallback_pickup',
    index: 0,
    stopType: isPickedUp ? 'dropoff' : 'pickup',
    stopJettyId: isPickedUp
        ? booking.destinationJettyId
        : booking.originJettyId,
    stopName: isPickedUp ? booking.destination : booking.origin,
    lat: isPickedUp ? booking.destinationLat : booking.originLat,
    lng: isPickedUp ? booking.destinationLng : booking.originLng,
    bookingIds: <String>[booking.bookingId],
    status: 'active',
  );
}

PoolStopPlanItem _fallbackDestinationStopFor(BookingModel booking) {
  return PoolStopPlanItem(
    stopId: 'fallback_destination',
    index: 1,
    stopType: 'dropoff',
    stopJettyId: booking.destinationJettyId,
    stopName: booking.destination,
    lat: booking.destinationLat,
    lng: booking.destinationLng,
    bookingIds: <String>[booking.bookingId],
  );
}

String _stopDisplayName(PoolStopPlanItem stop) {
  final stopName = stop.stopName.trim();
  final stopJettyId = stop.stopJettyId?.trim();
  final cleanJettyId = _cleanJettyId(stopJettyId);
  if (stopJettyId != null && stopJettyId.isNotEmpty && stopName.isNotEmpty) {
    return '$cleanJettyId - $stopName';
  }
  if (stopName.isNotEmpty) {
    return stopName;
  }
  if (stopJettyId != null && stopJettyId.isNotEmpty) return cleanJettyId;
  return stop.isPickup ? 'Pickup stop' : 'Dropoff stop';
}

String _cleanJettyId(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return raw;
  final match = RegExp(r'(\d+)$').firstMatch(raw);
  if (match != null) {
    return match.group(1)!;
  }
  return raw
      .replaceFirst(RegExp(r'^jetty[_\-\s]*', caseSensitive: false), '')
      .trim();
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

String _stopHeadlineActionLabel(
  PoolStopPlanItem stop,
  List<BookingModel> poolBookings,
) {
  final verb = stop.isPickup ? 'Pick up' : 'Drop off';
  final passengerCount = _stopPassengerCount(stop, poolBookings);
  if (passengerCount == 1) {
    return '$verb passenger';
  }
  return '$verb $passengerCount passengers';
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
  return 'Queued';
}

class _AlternatingStopHeadline extends StatefulWidget {
  const _AlternatingStopHeadline({
    required this.actionText,
    required this.stopText,
  });

  final String actionText;
  final String stopText;

  @override
  State<_AlternatingStopHeadline> createState() =>
      _AlternatingStopHeadlineState();
}

class _AlternatingStopHeadlineState extends State<_AlternatingStopHeadline> {
  Timer? _timer;
  bool _showStop = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted) {
        setState(() => _showStop = !_showStop);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AlternatingStopHeadline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionText != widget.actionText ||
        oldWidget.stopText != widget.stopText) {
      _showStop = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _showStop ? widget.stopText : widget.actionText;
    final color = _showStop ? OperatorBrand.magenta : Colors.grey[900]!;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _LoopingText(
        key: ValueKey(text),
        text: text,
        style: TextStyle(
          fontSize: 18,
          color: color,
          height: 1.15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CompactCollapsibleSection extends StatefulWidget {
  const _CompactCollapsibleSection({
    required this.title,
    required this.routeOrder,
  });

  final String title;
  final Widget routeOrder;

  @override
  State<_CompactCollapsibleSection> createState() =>
      _CompactCollapsibleSectionState();
}

class _CompactCollapsibleSectionState
    extends State<_CompactCollapsibleSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: OperatorBrand.magenta,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 19,
                  color: OperatorBrand.magenta,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: widget.routeOrder,
          ),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeOutCubic,
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class _LoopingText extends StatefulWidget {
  const _LoopingText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_LoopingText> createState() => _LoopingTextState();
}

class _LoopingTextState extends State<_LoopingText> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleLoop());
  }

  @override
  void didUpdateWidget(covariant _LoopingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      if (_controller.hasClients) {
        _controller.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleLoop());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleLoop() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 900), () async {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      await _controller.animateTo(
        maxExtent,
        duration: Duration(
          milliseconds: (maxExtent * 35).clamp(1800, 6500).round(),
        ),
        curve: Curves.linear,
      );
      if (!mounted || !_controller.hasClients) {
        return;
      }
      _timer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted || !_controller.hasClients) {
          return;
        }
        _controller.jumpTo(0);
        _scheduleLoop();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        ),
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
    required this.remaining,
    required this.eta,
    this.currentStopActionLabel,
    this.currentStopName,
    this.passengerContextLabel,
    this.miniTimelineLabel,
    this.routeDirectionLabel,
    required this.isUpdating,
    required this.primaryActionLabel,
    required this.routeWarningText,
    required this.onPrimaryAction,
  });

  final String remaining;
  final String eta;
  final String? currentStopActionLabel;
  final String? currentStopName;
  final String? passengerContextLabel;
  final String? miniTimelineLabel;
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
    final hasCurrentStop =
        widget.currentStopActionLabel != null || widget.currentStopName != null;
    final navigationTarget = hasCurrentStop
        ? '${widget.currentStopActionLabel ?? 'Continue'} @ ${widget.currentStopName ?? 'stop'}'
        : 'Navigation active';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              key: const ValueKey('now-navigating-header'),
              children: [
                const Icon(
                  Icons.navigation_rounded,
                  color: OperatorBrand.magenta,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Text(
                  'Now Navigating',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[900],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          if (hasCurrentStop) ...[
            _LoopingText(
              text: navigationTarget,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[900],
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
          ],
          _buildNavigationSummary('${widget.remaining} • ETA ${widget.eta}'),
          if (widget.routeWarningText != null) ...[
            const SizedBox(height: 7),
            _buildWarning(widget.routeWarningText!),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPrimaryActionBusy
                  ? null
                  : () => unawaited(_handlePrimaryAction()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: _isPrimaryActionBusy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(widget.primaryActionLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationSummary(String label) {
    return Row(
      children: [
        const Icon(Icons.route_rounded, size: 15, color: Colors.blueGrey),
        const SizedBox(width: 6),
        Expanded(
          child: _LoopingText(
            text: label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[800],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarning(String text) {
    final isMissedStop = text.toLowerCase().contains('missed stop');
    final background = isMissedStop
        ? const Color(0xFFFFF1F2)
        : const Color(0xFFFFF7ED);
    final foreground = isMissedStop
        ? const Color(0xFFB42318)
        : const Color(0xFF9A3412);
    final icon = isMissedStop
        ? Icons.warning_amber_rounded
        : Icons.info_outline_rounded;
    final alertText = isMissedStop ? _splitMissedStopWarning(text) : null;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMissedStop ? 12 : 10,
        vertical: isMissedStop ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(isMissedStop ? 12 : 8),
        border: isMissedStop
            ? Border.all(color: foreground.withValues(alpha: 0.18))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: isMissedStop ? 22 : 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: isMissedStop && alertText != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alertText.title,
                        style: TextStyle(
                          fontSize: 14,
                          color: foreground,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        alertText.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: foreground,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  _MissedStopWarning? _splitMissedStopWarning(String text) {
    final parts = text.split('.');
    final title = parts.isEmpty ? 'Missed stop' : parts.first.trim();
    final message = parts.length <= 1
        ? 'Return to the current stop.'
        : parts.skip(1).join('.').trim();
    return _MissedStopWarning(
      title: title.isEmpty ? 'Missed stop' : title,
      message: message.isEmpty ? 'Return to the current stop.' : message,
    );
  }
}

class _MissedStopWarning {
  const _MissedStopWarning({required this.title, required this.message});

  final String title;
  final String message;
}
