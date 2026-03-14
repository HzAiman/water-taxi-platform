import 'dart:async';

import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/services/notifications/local_notification_service.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class NotificationMessage {
  const NotificationMessage({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

typedef ForegroundNotifier = void Function(NotificationMessage message);

class OperatorNotificationCoordinator {
  OperatorNotificationCoordinator({
    required BookingRepository bookingRepo,
    required OperatorRepository operatorRepo,
    required LocalNotificationService localNotifications,
    required ForegroundNotifier onForegroundMessage,
  })  : _bookingRepo = bookingRepo,
        _operatorRepo = operatorRepo,
        _localNotifications = localNotifications,
        _onForegroundMessage = onForegroundMessage;

  final BookingRepository _bookingRepo;
  final OperatorRepository _operatorRepo;
  final LocalNotificationService _localNotifications;
  final ForegroundNotifier _onForegroundMessage;

  StreamSubscription<List<BookingModel>>? _pendingSub;
  StreamSubscription<List<BookingModel>>? _historySub;
  StreamSubscription<OperatorModel?>? _operatorSub;

  bool _isForeground = true;
  bool _isOnline = false;
  bool _seededPending = false;
  bool _seededHistory = false;

  Set<String> _knownPendingIds = <String>{};
  final Map<String, BookingStatus> _knownAssignedStatuses =
      <String, BookingStatus>{};

  Future<void> start({required String operatorId}) async {
    await _localNotifications.initialize();

    _operatorSub = _operatorRepo.streamOperator(operatorId).listen((op) async {
      final wasOnline = _isOnline;
      _isOnline = op?.isOnline ?? false;

      if (wasOnline != _isOnline) {
        if (_isOnline && !_isForeground) {
          await _localNotifications.showOnlineReminder(
            title: 'You are online',
            body: 'You can receive incoming booking requests.',
          );
        }
        if (!_isOnline) {
          await _localNotifications.cancelOnlineReminder();
        }
      }
    });

    _pendingSub = _bookingRepo.streamPendingBookings().listen((bookings) {
      final pendingIds = bookings.map((b) => b.bookingId).toSet();

      if (!_seededPending) {
        _knownPendingIds = pendingIds;
        _seededPending = true;
        return;
      }

      final newBookings = bookings
          .where((b) => !_knownPendingIds.contains(b.bookingId))
          .toList();
      _knownPendingIds = pendingIds;

      for (final booking in newBookings) {
        _deliver(
          NotificationMessage(
            title: 'Incoming booking request',
            body: '${booking.origin} to ${booking.destination}',
          ),
          eventId: booking.bookingId.hashCode,
          payload: booking.bookingId,
        );
      }
    });

    _historySub = _bookingRepo
        .streamOperatorBookingHistory(operatorId)
        .listen((bookings) {
      if (!_seededHistory) {
        for (final booking in bookings) {
          _knownAssignedStatuses[booking.bookingId] = booking.status;
        }
        _seededHistory = true;
        return;
      }

      for (final booking in bookings) {
        final previous = _knownAssignedStatuses[booking.bookingId];
        _knownAssignedStatuses[booking.bookingId] = booking.status;

        if (previous == null || previous == booking.status) {
          continue;
        }

        _deliver(
          NotificationMessage(
            title: 'Booking status updated',
            body: '${booking.bookingId}: ${_statusLabel(booking.status)}',
          ),
          eventId: booking.bookingId.hashCode,
          payload: booking.bookingId,
        );
      }
    });
  }

  Future<void> setForeground(bool isForeground) async {
    _isForeground = isForeground;

    if (_isForeground) {
      await _localNotifications.cancelOnlineReminder();
      return;
    }

    if (_isOnline) {
      await _localNotifications.showOnlineReminder(
        title: 'You are online',
        body: 'You can receive incoming booking requests.',
      );
    }
  }

  Future<void> _deliver(
    NotificationMessage message, {
    required int eventId,
    String? payload,
  }) async {
    if (_isForeground) {
      _onForegroundMessage(message);
      return;
    }

    await _localNotifications.showEvent(
      id: eventId,
      title: message.title,
      body: message.body,
      payload: payload,
    );
  }

  String _statusLabel(BookingStatus status) {
    return status.firestoreValue.replaceAll('_', ' ');
  }

  Future<void> dispose() async {
    await _pendingSub?.cancel();
    await _historySub?.cancel();
    await _operatorSub?.cancel();
    await _localNotifications.cancelOnlineReminder();
  }
}
