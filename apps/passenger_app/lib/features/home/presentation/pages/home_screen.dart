import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/data/repositories/fare_repository.dart';
import 'package:passenger_app/data/repositories/jetty_repository.dart';
import 'package:passenger_app/data/repositories/user_repository.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/jetty_location_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/payment_screen.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/home_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/payment_view_model.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasInitialized) {
        return;
      }

      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        return;
      }

      _hasInitialized = true;
      context.read<HomeViewModel>().init(userId);
    });
  }

  void _showBookingError(String message) {
    if (!mounted) {
      return;
    }
    showTopError(context, message: message);
  }

  List<Map<String, dynamic>> _toJettyMaps(List<JettyModel> jetties) {
    return jetties
        .map(
          (jetty) => <String, dynamic>{
            'name': jetty.name,
            'jettyId': jetty.jettyId,
            'lat': jetty.lat,
            'lng': jetty.lng,
          },
        )
        .toList();
  }

  void _handleOriginSelected(HomeViewModel viewModel, String selectedOrigin) {
    final destinationWasReset = viewModel.selectedDestination == selectedOrigin;
    viewModel.selectOrigin(selectedOrigin);

    if (destinationWasReset) {
      _showBookingError(
        'Drop-off location was reset. Please choose a different destination.',
      );
    }
  }

  void _handleDestinationSelected(
    HomeViewModel viewModel,
    String selectedDestination,
  ) {
    if (viewModel.selectedOrigin == selectedDestination) {
      _showBookingError('Pick-up and drop-off locations must be different.');
      return;
    }

    viewModel.selectDestination(selectedDestination);
  }

  Future<void> _bookNow(HomeViewModel viewModel) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showBookingError('Please sign in to continue.');
      return;
    }

    if (viewModel.selectedOrigin == null ||
        viewModel.selectedDestination == null) {
      _showBookingError('Please select both pick-up and drop-off locations.');
      return;
    }

    if (viewModel.selectedOrigin == viewModel.selectedDestination) {
      _showBookingError('Pick-up and drop-off locations cannot be the same.');
      return;
    }

    if (!viewModel.hasValidPassengerCount) {
      _showBookingError('Please select at least one passenger.');
      return;
    }

    if (viewModel.activeBooking != null) {
      _showBookingError(
        'You already have an active booking. Please view your current booking status first.',
      );
      return;
    }

    try {
      final fare = await viewModel.getFareForSelectedRoute();

      if (!mounted) {
        return;
      }

      if (fare == null) {
        _showBookingError(
          'No fare is available for this route yet. Please select another route.',
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => PaymentViewModel(
              fareRepo: context.read<FareRepository>(),
              jettyRepo: context.read<JettyRepository>(),
              userRepo: context.read<UserRepository>(),
              bookingRepo: context.read<BookingRepository>(),
            ),
            child: PaymentScreen(
              origin: viewModel.selectedOrigin!,
              destination: viewModel.selectedDestination!,
              adultCount: viewModel.adultCount,
              childCount: viewModel.childCount,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showBookingError(
        'Unable to verify fare for this route. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    final topInset = MediaQuery.of(context).padding.top;
    final jetties = _toJettyMaps(viewModel.jetties);
    final activeBooking = viewModel.activeBooking;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0xFF0066CC),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(24, topInset + 24, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0066CC),
                        const Color(0xFF0066CC).withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hello,',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        viewModel.userName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Where would you like to go today?',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActiveBookingCard(activeBooking),
                    const SizedBox(height: 20),
                    const Text(
                      'Pick-up Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDDE5F0),
                          width: 1.5,
                        ),
                      ),
                      child: viewModel.isLoadingJetties
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : viewModel.jettyError != null
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                viewModel.jettyError!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : DropdownButton<String>(
                              isExpanded: true,
                              value: viewModel.selectedOrigin,
                              hint: const Text('Select pick-up jetty'),
                              underline: const SizedBox(),
                              items: jetties.map((location) {
                                return DropdownMenuItem<String>(
                                  value: location['name'] as String,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        color: Color(0xFF0066CC),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Jetty ${location['jettyId']} - ${location['name']}',
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value == null) {
                                  return;
                                }
                                final result = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => JettyLocationScreen(
                                      initialJettyName: value,
                                      allJetties: jetties,
                                      isPickup: true,
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  _handleOriginSelected(viewModel, result);
                                }
                              },
                            ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Drop-off Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDDE5F0),
                          width: 1.5,
                        ),
                      ),
                      child: viewModel.isLoadingJetties
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : viewModel.jettyError != null
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                viewModel.jettyError!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : DropdownButton<String>(
                              isExpanded: true,
                              value: viewModel.selectedDestination,
                              hint: const Text('Select drop-off jetty'),
                              underline: const SizedBox(),
                              items: jetties.map((location) {
                                return DropdownMenuItem<String>(
                                  value: location['name'] as String,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.flag,
                                        color: Color(0xFF0066CC),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Jetty ${location['jettyId']} - ${location['name']}',
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) async {
                                if (value == null) {
                                  return;
                                }
                                final result = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => JettyLocationScreen(
                                      initialJettyName: value,
                                      allJetties: jetties,
                                      isPickup: false,
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  _handleDestinationSelected(viewModel, result);
                                }
                              },
                            ),
                    ),
                    if (viewModel.selectedOrigin != null &&
                        viewModel.selectedDestination != null &&
                        viewModel.selectedOrigin ==
                            viewModel.selectedDestination) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Text(
                          'Pick-up and drop-off locations must be different.',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Number of Passengers',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDDE5F0),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person,
                                color: Color(0xFF0066CC),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Adults',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Age 13 and above',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: viewModel.adultCount > 1
                                    ? const Color(0xFF0066CC)
                                    : Colors.grey,
                                onPressed: viewModel.adultCount > 1
                                    ? () => viewModel.setAdultCount(
                                        viewModel.adultCount - 1,
                                      )
                                    : null,
                              ),
                              Text(
                                '${viewModel.adultCount}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: viewModel.adultCount < 10
                                    ? const Color(0xFF0066CC)
                                    : Colors.grey,
                                onPressed: viewModel.adultCount < 10
                                    ? () => viewModel.setAdultCount(
                                        viewModel.adultCount + 1,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFDDE5F0),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.child_care,
                                color: Color(0xFF0066CC),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Children',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Age 12 and under',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: viewModel.childCount > 0
                                    ? const Color(0xFF0066CC)
                                    : Colors.grey,
                                onPressed: viewModel.childCount > 0
                                    ? () => viewModel.setChildCount(
                                        viewModel.childCount - 1,
                                      )
                                    : null,
                              ),
                              Text(
                                '${viewModel.childCount}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: viewModel.childCount < 10
                                    ? const Color(0xFF0066CC)
                                    : Colors.grey,
                                onPressed: viewModel.childCount < 10
                                    ? () => viewModel.setChildCount(
                                        viewModel.childCount + 1,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed:
                                (viewModel.canBook &&
                                    !viewModel.isCheckingFare &&
                                    activeBooking == null)
                                ? () => _bookNow(viewModel)
                                : null,
                            child: viewModel.isCheckingFare
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Book Water Taxi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        if (activeBooking != null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'You have an active booking. Open View Booking Status above to continue.',
                            style: TextStyle(
                              color: Color(0xFF8A5A00),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (viewModel.isCheckingFare) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Checking fare availability for this route...',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveBookingCard(BookingModel? booking) {
    if (booking == null || !booking.status.isActive) {
      return const SizedBox.shrink();
    }

    final bookingId = booking.bookingId.isNotEmpty
        ? booking.bookingId
        : 'Current booking';
    final statusColor = _statusColor(booking.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFD7F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long,
                color: Color(0xFF0066CC),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Current Booking',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatStatusLabel(booking.status.firestoreValue),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${booking.origin} -> ${booking.destination}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2A2A2A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Booking ID: $bookingId | Passengers: ${booking.passengerCount}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                      create: (_) => BookingTrackingViewModel(
                        bookingRepo: context.read<BookingRepository>(),
                      ),
                      child: BookingTrackingScreen(
                        bookingId: booking.bookingId,
                        origin: booking.origin,
                        destination: booking.destination,
                        passengerCount: booking.passengerCount,
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.directions_boat, size: 18),
              label: const Text('View Booking Status'),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatStatusLabel(String status) {
    return status
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return Colors.orange;
      case BookingStatus.accepted:
        return const Color(0xFF0066CC);
      case BookingStatus.completed:
        return Colors.green;
      case BookingStatus.cancelled:
        return Colors.red;
      case BookingStatus.onTheWay:
        return Colors.teal;
      case BookingStatus.rejected:
        return Colors.deepOrange;
      case BookingStatus.unknown:
        return const Color(0xFF666666);
    }
  }
}
