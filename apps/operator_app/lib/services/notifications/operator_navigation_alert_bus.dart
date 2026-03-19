import 'dart:async';

class OperatorNavigationAlert {
  const OperatorNavigationAlert({
    required this.eventId,
    required this.bookingId,
    required this.title,
    required this.body,
  });

  final int eventId;
  final String bookingId;
  final String title;
  final String body;
}

class OperatorNavigationAlertBus {
  OperatorNavigationAlertBus._();

  static final StreamController<OperatorNavigationAlert> _controller =
      StreamController<OperatorNavigationAlert>.broadcast();

  static Stream<OperatorNavigationAlert> get stream => _controller.stream;

  static void publish(OperatorNavigationAlert alert) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(alert);
  }
}
