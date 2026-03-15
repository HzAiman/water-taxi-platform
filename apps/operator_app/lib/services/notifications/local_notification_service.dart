import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService();

  static const String _eventsChannelId = 'operator_booking_events';
  static const String _eventsChannelName = 'Booking Events';
  static const String _eventsChannelDesc =
      'Notifications for incoming requests and booking updates';

  static const String _reminderChannelId = 'operator_online_reminder';
  static const String _reminderChannelName = 'Online Reminder';
  static const String _reminderChannelDesc =
      'Persistent reminder when operator is online';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Static tap handler — set by MainScreen so OS-notification taps navigate
  // to the home tab (booking list) when the operator taps a notification.
  // ---------------------------------------------------------------------------

  static void Function(String payload)? _onTap;

  static void setOnTapHandler(void Function(String payload) handler) {
    _onTap = handler;
  }

  @pragma('vm:entry-point')
  static void _onDidReceiveNotificationResponse(
      NotificationResponse details) {
    final payload = details.payload;
    if (payload != null && payload.isNotEmpty) _onTap?.call(payload);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse:
          LocalNotificationService._onDidReceiveNotificationResponse,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  /// Returns the payload of the local notification that launched the app from
  /// a terminated state, or `null` if the app was not launched from one.
  ///
  /// **Must be called BEFORE [initialize].**
  Future<String?> getLaunchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  // ---------------------------------------------------------------------------
  // Show helpers
  // ---------------------------------------------------------------------------

  Future<void> showEvent({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _eventsChannelId,
          _eventsChannelName,
          channelDescription: _eventsChannelDesc,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  Future<void> showOnlineReminder({
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      1,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          _reminderChannelName,
          channelDescription: _reminderChannelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.service,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          onlyAlertOnce: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  Future<void> cancelOnlineReminder() => _plugin.cancel(1);
}
