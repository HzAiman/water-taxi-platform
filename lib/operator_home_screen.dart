import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({super.key});

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  bool _isOnline = false;
  bool _isToggling = false;
  bool _hasLocationPermission = false;
  bool _mapReady = false;
  late GoogleMapController _mapController;
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(3.1390, 101.6869), // fallback to KL
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _bootstrapLocation();
  }

  Future<void> _bootstrapLocation() async {
    final granted = await _ensureLocationPermission();
    if (!granted) return;

    try {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _initialCameraPosition = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: 16,
        );
      });

      // If map is already ready, move camera immediately
      if (_mapReady) {
        _mapController.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(pos.latitude, pos.longitude),
            16,
          ),
        );
      }
    } catch (e) {
      // Keep fallback position; surface a gentle notice
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to get current location: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _ensureLocationPermission() async {
    // Ensure location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are off. Enable them to show your position.'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
      }
      setState(() => _hasLocationPermission = false);
      return false;
    }

    // Check and request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permission denied forever. Enable it in Settings.'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: openAppSettings,
            ),
          ),
        );
      }
      setState(() => _hasLocationPermission = false);
      return false;
    }

    final granted = permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    if (mounted) setState(() => _hasLocationPermission = granted);
    return granted;
  }

  Future<void> _centerOnUser() async {
    if (!_mapReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map is still loading.')),
      );
      return;
    }

    // Ensure permission before requesting location
    final granted = await _ensureLocationPermission();
    if (!granted) return;

    try {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to get location: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nextStatus = !_isOnline;

    // Optimistic UI update for faster feedback
    setState(() {
      _isToggling = true;
      _isOnline = nextStatus;
    });

    try {
      await FirebaseFirestore.instance
          .collection('operators')
          .doc(user.uid)
          .set({
        'isOnline': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
    } on TimeoutException {
      if (mounted) {
        setState(() => _isOnline = !nextStatus); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updating status timed out. Check your network.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = !nextStatus); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
      ),
      body: user == null
          ? const Center(child: Text('Not signed in'))
          : Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    key: const ValueKey('operator-map'),
                    initialCameraPosition: _initialCameraPosition,
                    myLocationEnabled: _hasLocationPermission,
                    myLocationButtonEnabled: false,
                    compassEnabled: true,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      _mapReady = true;
                    },
                  ),
                ),
                // Welcome Card
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.0, end: 0.0),
                    duration: const Duration(seconds: 6),
                    curve: Curves.easeInExpo,
                    builder: (context, value, child) {
                      if (value <= 0.01) return const SizedBox.shrink();
                      return Opacity(
                        opacity: value > 0.2 ? 1.0 : value * 5,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user, color: Color(0xFF0066CC), size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Welcome back, Operator!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      user.email ?? 'Operator',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('operators')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data();
                      if (data != null && data['isOnline'] is bool && !_isToggling) {
                        _isOnline = data['isOnline'] as bool;
                      }

                      final loadingSnapshot = snapshot.connectionState == ConnectionState.waiting;
                      final buttonLabel = _isOnline ? 'Go Offline' : 'Go Online';

                      return Stack(
                        children: [
                          if (loadingSnapshot)
                            const Center(child: CircularProgressIndicator()),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 24,
                            child: Center(
                              child: ElevatedButton.icon(
                                onPressed: (_isToggling || loadingSnapshot) ? null : _toggleStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _isOnline ? Colors.red : const Color(0xFF0066CC),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _isToggling
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(Icons.power_settings_new),
                                label: Text(
                                  buttonLabel,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Positioned(
                  bottom: 100,
                  right: 16,
                  child: FloatingActionButton(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
    );
  }
}
