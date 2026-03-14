import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/home_screen.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:passenger_app/services/notifications/local_notification_service.dart';
import 'package:passenger_app/services/notifications/passenger_notification_coordinator.dart';
import 'package:passenger_app/services/notifications/push_notification_service.dart';
import 'package:provider/provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  PassengerNotificationCoordinator? _notificationCoordinator;
  PushNotificationService? _pushNotificationService;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (!mounted || userId == null) return;

      final bookingRepo = context.read<BookingRepository>();

      // Check for a local-notification launch payload BEFORE initialize().
      final localNotifications = LocalNotificationService();
      final launchPayload = await localNotifications.getLaunchPayload();

      _notificationCoordinator = PassengerNotificationCoordinator(
        bookingRepo: bookingRepo,
        localNotifications: localNotifications,
        onForegroundMessage: (message) {
          if (!mounted) return;
          showTopInfo(
            context,
            title: message.title,
            message: message.body,
          );
        },
      );
      await _notificationCoordinator?.start(userId: userId);

      // Register tap handler for background -> foreground local notification taps.
      LocalNotificationService.setOnTapHandler(_handleNotificationTap);

      // Handle FCM tap from terminated state.
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (!mounted) return;
      if (initialMessage != null) _handleFcmTap(initialMessage);

      // Handle local notification tap from terminated state.
      if (launchPayload != null) _handleNotificationTap(launchPayload);

      // Handle FCM tap from background state.
      _fcmOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);

      _pushNotificationService = PushNotificationService();
      _pushNotificationService?.startForPassenger(
        userId,
        onForegroundMessage: (title, body) {
          if (!mounted) return;
          showTopInfo(context, title: title, message: body);
        },
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _notificationCoordinator?.setForeground(isForeground);
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fcmOpenedSub?.cancel();
    _notificationCoordinator?.dispose();
    super.dispose();
  }

  void _handleFcmTap(RemoteMessage message) {
    final data = message.data;
    final bookingId = data['bookingId'] as String?;
    if (bookingId == null) return;
    _navigateToBooking(
      bookingId: bookingId,
      origin: data['origin'] as String? ?? '',
      destination: data['destination'] as String? ?? '',
      passengerCount:
          int.tryParse(data['passengerCount'] as String? ?? '') ?? 1,
    );
  }

  // Called for local-notification taps (payload = bookingId only).
  void _handleNotificationTap(String bookingId) {
    _navigateToBooking(
        bookingId: bookingId, origin: '', destination: '', passengerCount: 1);
  }

  void _navigateToBooking({
    required String bookingId,
    required String origin,
    required String destination,
    required int passengerCount,
  }) {
    if (!mounted) return;
    final bookingRepo = context.read<BookingRepository>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => BookingTrackingViewModel(bookingRepo: bookingRepo),
          child: BookingTrackingScreen(
            bookingId: bookingId,
            origin: origin,
            destination: destination,
            passengerCount: passengerCount,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outlined),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
