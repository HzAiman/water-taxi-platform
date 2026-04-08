import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/data/repositories/booking_repository.dart';
import 'package:operator_app/data/repositories/operator_repository.dart';
import 'package:operator_app/features/home/presentation/pages/operator_home_screen.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_profile_page.dart';
import 'package:operator_app/services/notifications/local_notification_service.dart';
import 'package:operator_app/services/notifications/operator_navigation_alert_bus.dart';
import 'package:operator_app/services/notifications/operator_notification_coordinator.dart';
import 'package:operator_app/services/notifications/push_notification_service.dart';
import 'package:provider/provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  OperatorNotificationCoordinator? _notificationCoordinator;
  PushNotificationService? _pushNotificationService;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;
  StreamSubscription<OperatorNavigationAlert>? _navigationAlertSub;

  final List<Widget> _screens = const [
    OperatorHomeScreen(),
    OperatorProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final currentUser = FirebaseAuth.instance.currentUser;
      final operatorId = currentUser?.uid;
      if (!mounted || operatorId == null) return;

      final bookingRepo = context.read<BookingRepository>();
      final operatorRepo = context.read<OperatorRepository>();

      // Check for a local-notification launch payload BEFORE initialize().
      final localNotifications = LocalNotificationService();
      final launchPayload = await localNotifications.getLaunchPayload();

      _notificationCoordinator = OperatorNotificationCoordinator(
        bookingRepo: bookingRepo,
        operatorRepo: operatorRepo,
        localNotifications: localNotifications,
        onForegroundMessage: (message) {
          if (!mounted) return;
          showTopInfo(context, title: message.title, message: message.body);
        },
      );
      await _notificationCoordinator?.start(operatorId: operatorId);

      _navigationAlertSub = OperatorNavigationAlertBus.stream.listen((alert) {
        _notificationCoordinator?.deliverNavigationAlert(alert);
      });

      // Register tap handler for background -> foreground local notification taps.
      LocalNotificationService.setOnTapHandler(_handleNotificationTap);

      // Handle FCM tap from terminated state.
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (!mounted) return;
      if (initialMessage != null) {
        _handleNotificationTap(
          initialMessage.data['bookingId'] as String? ?? '',
        );
      }

      // Handle local notification tap from terminated state.
      if (launchPayload != null) _handleNotificationTap(launchPayload);

      // Handle FCM tap from background state.
      _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _handleNotificationTap(msg.data['bookingId'] as String? ?? ''),
      );

      _pushNotificationService = PushNotificationService();
      _pushNotificationService?.startForOperator(
        operatorId,
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
    _navigationAlertSub?.cancel();
    _notificationCoordinator?.dispose();
    super.dispose();
  }

  // Notification tap -> switch to home tab where bookings are managed.
  void _handleNotificationTap(String bookingId) {
    if (!mounted) return;
    setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: [
          BottomNavigationBarItem(
            icon: Icon(_selectedIndex == 0 ? Icons.home : Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              _selectedIndex == 1 ? Icons.person : Icons.person_outlined,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
