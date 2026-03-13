import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/payment_screen.dart';
import 'package:passenger_app/jetty_location_screen.dart';
import 'package:passenger_app/widgets/top_alert.dart';

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

  Future<void> _bookNow() async {
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
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: (_canBookNow && !_isCheckingFare)
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
}