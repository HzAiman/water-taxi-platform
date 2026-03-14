import 'dart:async';

import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/services/notifications/local_notification_service.dart';
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

class PassengerNotificationCoordinator {
  PassengerNotificationCoordinator({
    required BookingRepository bookingRepo,
    required LocalNotificationService localNotifications,
    required ForegroundNotifier onForegroundMessage,
  })  : _bookingRepo = bookingRepo,
        _localNotifications = localNotifications,
        _onForegroundMessage = onForegroundMessage;

  final BookingRepository _bookingRepo;
  final LocalNotificationService _localNotifications;
  final ForegroundNotifier _onForegroundMessage;

  StreamSubscription<List<BookingModel>>? _historySub;
  bool _isForeground = true;
  bool _seeded = false;
  final Map<String, BookingStatus> _knownStatuses = <String, BookingStatus>{};

  Future<void> start({required String userId}) async {
    await _localNotifications.initialize();

    _historySub =
        _bookingRepo.streamUserBookingHistory(userId).listen((bookings) {
      if (!_seeded) {
        for (final booking in bookings) {
          _knownStatuses[booking.bookingId] = booking.status;
        }
        _seeded = true;
        return;
      }

      for (final booking in bookings) {
        final previous = _knownStatuses[booking.bookingId];
        _knownStatuses[booking.bookingId] = booking.status;

        if (previous == null || previous == booking.status) {
          continue;
        }

        _deliver(
          NotificationMessage(
            title: 'Booking status updated',
            body:
                '${booking.origin} to ${booking.destination}: ${_labelForStatus(booking.status)}',
          ),
          eventId: booking.bookingId.hashCode,
          payload: booking.bookingId,
        );
      }
    });
  }

  void setForeground(bool isForeground) {
    _isForeground = isForeground;
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

    await _localNotifications.showBookingUpdate(
      id: eventId,
      title: message.title,
      body: message.body,
      payload: payload,
    );
  }

  String _labelForStatus(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return 'Waiting for operator';
      case BookingStatus.accepted:
        return 'Accepted by operator';
      case BookingStatus.onTheWay:
        return 'Operator is on the way';
      case BookingStatus.completed:
        return 'Trip completed';
      case BookingStatus.cancelled:
        return 'Booking cancelled';
      case BookingStatus.rejected:
        return 'No operator available';
      case BookingStatus.unknown:
        return status.firestoreValue;
    }
  }

  Future<void> dispose() async {
    await _historySub?.cancel();
  }
}
