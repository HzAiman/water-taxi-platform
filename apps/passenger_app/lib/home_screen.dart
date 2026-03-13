import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/payment_screen.dart';
import 'package:passenger_app/jetty_location_screen.dart';

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
                                        setState(() {
                                          _selectedOrigin = result;
                                        });
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
                                        setState(() {
                                          _selectedDestination = result;
                                        });
                                      }
                                    }
                                  },
                                ),
                    ),
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
                        onPressed: (_selectedOrigin != null && _selectedDestination != null && (_adultCount > 0 || _childCount > 0))
                            ? () {
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
                              }
                            : null,
                        child: const Text(
                          "Book Water Taxi",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
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