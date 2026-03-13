import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/jetty_location_screen.dart';
import 'package:passenger_app/features/home/presentation/pages/payment_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = 'Passenger';
  String? _selectedOrigin;
  String? _selectedDestination;
  int _adultCount = 1;
  int _childCount = 0;

  List<Map<String, dynamic>> _locations = [];
  bool _isLoadingLocations = true;
  String? _locationError;
  bool _isCheckingFare = false;

  bool get _hasValidPassengerCount => (_adultCount + _childCount) > 0;

  bool get _isRouteReady =>
      _selectedOrigin != null &&
      _selectedDestination != null &&
      _selectedOrigin != _selectedDestination;

  bool get _canBookNow => _isRouteReady && _hasValidPassengerCount;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadLocations();
  }

  Future<void> _loadUserData() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists && mounted) {
        setState(() {
          _userName = userDoc.data()?['name'] ?? 'Passenger';
        });
      }
    }
  }

  Future<void> _loadLocations() async {
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('jetties')
          .orderBy('jettyId')
          .get();

      if (mounted) {
        setState(() {
          _locations = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            return <String, dynamic>{
              'name': (data?['name'] ?? '').toString(),
              'jettyId': data?['jettyId']?.toString() ?? '',
              'lat': (data?['lat'] ?? 0.0) as num,
              'lng': (data?['lng'] ?? 0.0) as num,
            };
          }).toList()
            ..sort((a, b) {
              final ai = double.tryParse((a['jettyId'] ?? '').toString()) ?? double.infinity;
              final bi = double.tryParse((b['jettyId'] ?? '').toString()) ?? double.infinity;
              if (ai != bi) return ai.compareTo(bi);
              return (a['name'] as String).compareTo(b['name'] as String);
            });
          _isLoadingLocations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Failed to load jetties';
          _isLoadingLocations = false;
        });
      }
    }
  }

  void _showBookingError(String message) {
    if (!mounted) return;
    showTopError(context, message: message);
  }

  void _handleOriginSelected(String selectedOrigin) {
    final destinationWasReset = _selectedDestination == selectedOrigin;

    setState(() {
      _selectedOrigin = selectedOrigin;
      if (destinationWasReset) {
        _selectedDestination = null;
      }
    });

    if (destinationWasReset) {
      _showBookingError('Drop-off location was reset. Please choose a different destination.');
    }
  }

  void _handleDestinationSelected(String selectedDestination) {
    if (_selectedOrigin != null && _selectedOrigin == selectedDestination) {
      _showBookingError('Pick-up and drop-off locations must be different.');
      return;
    }

    setState(() {
      _selectedDestination = selectedDestination;
    });
  }

  Future<bool> _hasFareForRoute({
    required String origin,
    required String destination,
  }) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('fares')
        .where('origin', isEqualTo: origin)
        .where('destination', isEqualTo: destination)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> _hasActiveBookingForUser(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs.any((doc) {
      final status = (doc.data()['status'] ?? '').toString().toLowerCase();
      return _isActiveBookingStatus(status);
    });
  }

  Future<void> _bookNow() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showBookingError('Please sign in to continue.');
      return;
    }

    if (_selectedOrigin == null || _selectedDestination == null) {
      _showBookingError('Please select both pick-up and drop-off locations.');
      return;
    }

    if (_selectedOrigin == _selectedDestination) {
      _showBookingError('Pick-up and drop-off locations cannot be the same.');
      return;
    }

    if (!_hasValidPassengerCount) {
      _showBookingError('Please select at least one passenger.');
      return;
    }

    final hasActiveBooking = await _hasActiveBookingForUser(currentUser.uid);
    if (!mounted) {
      return;
    }
    if (hasActiveBooking) {
      _showBookingError('You already have an active booking. Please view your current booking status first.');
      return;
    }

    setState(() {
      _isCheckingFare = true;
    });

    try {
      final hasFare = await _hasFareForRoute(
        origin: _selectedOrigin!,
        destination: _selectedDestination!,
      );

      if (!mounted) {
        return;
      }

      if (!hasFare) {
        _showBookingError('No fare is available for this route yet. Please select another route.');
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            origin: _selectedOrigin!,
            destination: _selectedDestination!,
            adultCount: _adultCount,
            childCount: _childCount,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      _showBookingError('Unable to verify fare for this route. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingFare = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0xFF0066CC),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting Section
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
                      Text(
                        "Hello,",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Where would you like to go today?",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Booking Form Section
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildActiveBookingCard(),
                    const SizedBox(height: 20),
                    // Origin Selection
                    const Text(
                      "Pick-up Location",
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
                        border: Border.all(color: const Color(0xFFDDE5F0), width: 1.5),
                      ),
                      child: _isLoadingLocations
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _locationError != null
                              ? Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    _locationError!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                )
                              : DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedOrigin,
                                  hint: const Text("Select pick-up jetty"),
                                  underline: const SizedBox(),
                                  items: _locations.map((location) {
                                    return DropdownMenuItem<String>(
                                      value: location['name'],
                                      child: Row(
                                        children: [
                                          const Icon(Icons.location_on, color: Color(0xFF0066CC), size: 20),
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
                                    if (value != null) {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => JettyLocationScreen(
                                            initialJettyName: value,
                                            allJetties: _locations,
                                            isPickup: true,
                                          ),
                                        ),
                                      );
                                      if (result != null && mounted) {
                                        _handleOriginSelected(result);
                                      }
                                    }
                                  },
                                ),
                    ),
                    const SizedBox(height: 20),

                    // Destination Selection
                    const Text(
                      "Drop-off Location",
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
                        border: Border.all(color: const Color(0xFFDDE5F0), width: 1.5),
                      ),
                      child: _isLoadingLocations
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _locationError != null
                              ? Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    _locationError!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                )
                              : DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedDestination,
                                  hint: const Text("Select drop-off jetty"),
                                  underline: const SizedBox(),
                                  items: _locations.map((location) {
                                    return DropdownMenuItem<String>(
                                      value: location['name'],
                                      child: Row(
                                        children: [
                                          const Icon(Icons.flag, color: Color(0xFF0066CC), size: 20),
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
                                    if (value != null) {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => JettyLocationScreen(
                                            initialJettyName: value,
                                            allJetties: _locations,
                                            isPickup: false,
                                          ),
                                        ),
                                      );
                                      if (result != null && mounted) {
                                        _handleDestinationSelected(result);
                                      }
                                    }
                                  },
                                ),
                    ),
                    if (_selectedOrigin != null &&
                        _selectedDestination != null &&
                        _selectedOrigin == _selectedDestination) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
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

                    // Number of Passengers
                    const Text(
                      "Number of Passengers",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Adults
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDE5F0), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, color: Color(0xFF0066CC)),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Adults',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Age 13 and above',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: _adultCount > 1 ? const Color(0xFF0066CC) : Colors.grey,
                                onPressed: _adultCount > 1
                                    ? () {
                                        setState(() => _adultCount--);
                                      }
                                    : null,
                              ),
                              Text(
                                '$_adultCount',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: _adultCount < 10 ? const Color(0xFF0066CC) : Colors.grey,
                                onPressed: _adultCount < 10
                                    ? () {
                                        setState(() => _adultCount++);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Children
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDE5F0), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.child_care, color: Color(0xFF0066CC)),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Children',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Age 12 and under',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: _childCount > 0 ? const Color(0xFF0066CC) : Colors.grey,
                                onPressed: _childCount > 0
                                    ? () {
                                        setState(() => _childCount--);
                                      }
                                    : null,
                              ),
                              Text(
                                '$_childCount',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: _childCount < 10 ? const Color(0xFF0066CC) : Colors.grey,
                                onPressed: _childCount < 10
                                    ? () {
                                        setState(() => _childCount++);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Book Now Button
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseAuth.instance.currentUser == null
                          ? null
                          : FirebaseFirestore.instance
                              .collection('bookings')
                              .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
                              .snapshots(includeMetadataChanges: true),
                      builder: (context, snapshot) {
                        final hasActiveBooking = snapshot.hasData
                            ? snapshot.data!.docs.any((doc) {
                                final status = (doc.data()['status'] ?? '').toString().toLowerCase();
                                return _isActiveBookingStatus(status);
                              })
                            : false;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: (_canBookNow && !_isCheckingFare && !hasActiveBooking)
                                    ? _bookNow
                                    : null,
                                child: _isCheckingFare
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        "Book Water Taxi",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            if (hasActiveBooking) ...[
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
                        );
                      },
                    ),
                    if (_isCheckingFare) ...[
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

  Widget _buildActiveBookingCard() {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: currentUser.uid)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final activeDocs = snapshot.data!.docs.where((doc) {
          final status = (doc.data()['status'] ?? '').toString().toLowerCase();
          return _isActiveBookingStatus(status);
        }).toList()
          ..sort((a, b) {
            final aTimestamp = a.data()['createdAt'];
            final bTimestamp = b.data()['createdAt'];
            if (aTimestamp is Timestamp && bTimestamp is Timestamp) {
              return bTimestamp.compareTo(aTimestamp);
            }
            if (bTimestamp is Timestamp) return 1;
            if (aTimestamp is Timestamp) return -1;
            return 0;
          });

        if (activeDocs.isEmpty) {
          return const SizedBox.shrink();
        }

        final bookingDoc = activeDocs.first;
        final booking = bookingDoc.data();
        final bookingId = (booking['bookingId'] ?? bookingDoc.id).toString();
        final origin = (booking['origin'] ?? 'Unknown origin').toString();
        final destination = (booking['destination'] ?? 'Unknown destination').toString();
        final passengerCount = _toInt(booking['passengerCount']) ?? 1;
        final status = (booking['status'] ?? 'pending').toString();
        final statusColor = _statusColor(status);

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
                  const Icon(Icons.receipt_long, color: Color(0xFF0066CC), size: 20),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatStatusLabel(status),
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
                '$origin -> $destination',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2A2A2A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Booking ID: $bookingId | Passengers: $passengerCount',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingTrackingScreen(
                          bookingId: bookingDoc.id,
                          origin: origin,
                          destination: destination,
                          passengerCount: passengerCount,
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
      },
    );
  }

  static bool _isActiveBookingStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'confirmed':
      case 'accepted':
      case 'on_the_way':
      case 'in_progress':
      case 'ongoing':
        return true;
      default:
        return false;
    }
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String _formatStatusLabel(String status) {
    return status
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
      case 'accepted':
        return const Color(0xFF0066CC);
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'on_the_way':
      case 'in_progress':
      case 'ongoing':
        return Colors.teal;
      default:
        return const Color(0xFF666666);
    }
  }
}