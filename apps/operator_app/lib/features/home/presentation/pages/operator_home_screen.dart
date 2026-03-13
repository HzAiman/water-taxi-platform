import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:permission_handler/permission_handler.dart';

class OperatorHomeScreen extends StatefulWidget {
  const OperatorHomeScreen({super.key});

  @override
  State<OperatorHomeScreen> createState() => _OperatorHomeScreenState();
}

class _OperatorHomeScreenState extends State<OperatorHomeScreen> {
  static const MethodChannel _mapsConfigChannel = MethodChannel('operator_app/maps_config');

  bool _isOnline = false;
  bool _isToggling = false;
  bool _isUpdatingBooking = false;
  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _mapReady = false;
  late GoogleMapController _mapController;
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(3.1390, 101.6869),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasShownWelcomeAlert) {
        return;
      }
      final operatorLabel = FirebaseAuth.instance.currentUser?.email ?? 'Operator';
      showTopWelcomeCard(context, operatorLabel: operatorLabel);
      _hasShownWelcomeAlert = true;
      _checkMapsConfiguration();
    });
    _bootstrapLocation();
  }

  Future<void> _checkMapsConfiguration() async {
    if (!mounted || _hasCheckedMapsConfig) {
      return;
    }
    _hasCheckedMapsConfig = true;

    try {
      final result = await _mapsConfigChannel.invokeMapMethod<String, dynamic>('getMapsConfigStatus');
      if (!mounted || result == null) {
        return;
      }

      final injected = result['injected'] == true;
      if (!injected) {
        showTopError(
          context,
          title: 'Google Maps key not injected',
          message:
              'MAPS_API_KEY is not resolved from Android manifest. Check android/local.properties and API key restrictions.',
        );
        return;
      }

      if (kDebugMode) {
        final preview = (result['preview'] ?? '').toString();
        debugPrint('Operator Maps API key injected: $preview');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Maps config check failed: $e');
      }
    }
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

      if (_mapReady) {
        _mapController.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showTopError(context, message: 'Unable to get current location: $e', title: 'Location error');
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        showTopInfo(
          context,
          title: 'Location services off',
          message: 'Enable location services to show your position.',
          actionLabel: 'Open Settings',
          onAction: Geolocator.openLocationSettings,
        );
      }
      setState(() => _hasLocationPermission = false);
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showTopInfo(
          context,
          title: 'Permission required',
          message: 'Location permission was denied permanently. Enable it in Settings.',
          actionLabel: 'Open Settings',
          onAction: openAppSettings,
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
      showTopInfo(context, message: 'Map is still loading.', title: 'Please wait');
      return;
    }

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
      showTopError(context, message: 'Unable to get location: $e', title: 'Location error');
    }
  }

  Future<void> _toggleStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nextStatus = !_isOnline;

    setState(() {
      _isToggling = true;
      _isOnline = nextStatus;
    });

    try {
      await FirebaseFirestore.instance.collection('operators').doc(user.uid).set({
        'isOnline': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));

      if (!mounted) {
        return;
      }

      if (!nextStatus) {
        showTopOfflineCard(context);
      } else {
        showTopInfo(
          context,
          title: 'You are online',
          message: 'Waiting for passengers and new bookings.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isOnline = !nextStatus);
        showTopError(context, message: 'Updating status timed out. Check your network.', title: 'Status update failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = !nextStatus);
        showTopError(context, message: 'Failed to update status: $e', title: 'Status update failed');
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _updateBookingStatus({
    required String bookingId,
    required String status,
    String? driverId,
  }) async {
    if (_isUpdatingBooking) {
      return;
    }

    setState(() => _isUpdatingBooking = true);
    try {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'status': status,
        'driverId': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      showTopSuccess(context, message: 'Booking status updated to ${_formatStatusLabel(status)}.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      showTopError(context, message: 'Failed to update booking: $e', title: 'Booking update failed');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingBooking = false);
      }
    }
  }

  Widget _buildBookingActionCard(String userId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('bookings').snapshots(includeMetadataChanges: true),
      builder: (context, bookingSnapshot) {
        if (bookingSnapshot.hasError) {
          return _buildInfoCard(
            icon: Icons.error_outline,
            iconColor: Colors.red,
            title: 'Unable to load bookings',
            subtitle: 'Please check your connection and try again.',
          );
        }

        final docs = bookingSnapshot.data?.docs ?? const [];
        final pendingDocs = docs.where((doc) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          final driverId = data['driverId'];
          return status == 'pending' && (driverId == null || driverId.toString().isEmpty);
        }).toList();

        final activeAssignedDocs = docs.where((doc) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          final driverId = (data['driverId'] ?? '').toString();
          return driverId == userId && (status == 'accepted' || status == 'on_the_way');
        }).toList();

        pendingDocs.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return aTs.compareTo(bTs);
          }
          return 0;
        });

        activeAssignedDocs.sort((a, b) {
          final aTs = a.data()['updatedAt'];
          final bTs = b.data()['updatedAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }
          return 0;
        });

        if (activeAssignedDocs.isNotEmpty) {
          final bookingDoc = activeAssignedDocs.first;
          final booking = bookingDoc.data();
          final status = (booking['status'] ?? 'accepted').toString();
          final routeLabel =
              '${(booking['origin'] ?? 'Unknown').toString()} -> ${(booking['destination'] ?? 'Unknown').toString()}';
          final passengerCount = _toInt(booking['passengerCount']) ?? 1;

          final actionLabel = status.toLowerCase() == 'accepted' ? 'Start Trip' : 'Complete Trip';
          final nextStatus = status.toLowerCase() == 'accepted' ? 'on_the_way' : 'completed';
          final actionColor = status.toLowerCase() == 'accepted' ? const Color(0xFF0066CC) : Colors.green;

          return _buildInfoCard(
            icon: status.toLowerCase() == 'accepted' ? Icons.directions_boat : Icons.route,
            iconColor: actionColor,
            title: 'Current Booking: ${_formatStatusLabel(status)}',
            subtitle: '$routeLabel\nPassengers: $passengerCount',
            actionLabel: actionLabel,
            actionColor: actionColor,
            onAction: _isUpdatingBooking
                ? null
                : () => _updateBookingStatus(
                      bookingId: bookingDoc.id,
                      status: nextStatus,
                      driverId: userId,
                    ),
          );
        }

        if (pendingDocs.isNotEmpty) {
          final bookingDoc = pendingDocs.first;
          final booking = bookingDoc.data();
          final routeLabel =
              '${(booking['origin'] ?? 'Unknown').toString()} -> ${(booking['destination'] ?? 'Unknown').toString()}';
          final passengerCount = _toInt(booking['passengerCount']) ?? 1;

          return _buildInfoCard(
            icon: Icons.notifications_active,
            iconColor: Colors.orange,
            title: 'New Pending Booking',
            subtitle: '$routeLabel\nPassengers: $passengerCount',
            actionLabel: 'Accept Booking',
            actionColor: const Color(0xFF0066CC),
            onAction: _isUpdatingBooking
                ? null
                : () => _updateBookingStatus(
                      bookingId: bookingDoc.id,
                      status: 'accepted',
                      driverId: userId,
                    ),
          );
        }

        return _buildInfoCard(
          icon: Icons.hourglass_top,
          iconColor: Colors.orange,
          title: 'Waiting for booking',
          subtitle: 'You are online. Waiting for passengers...',
        );
      },
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? actionLabel,
    Color actionColor = const Color(0xFF0066CC),
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                ),
                child: _isUpdatingBooking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
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
                Positioned.fill(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('operators').doc(user.uid).snapshots(),
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data();
                      if (data != null && data['isOnline'] is bool && !_isToggling) {
                        _isOnline = data['isOnline'] as bool;
                      }

                      final loadingSnapshot = snapshot.connectionState == ConnectionState.waiting;
                      final buttonLabel = _isOnline ? 'Go Offline' : 'Go Online';

                      return Stack(
                        children: [
                          if (loadingSnapshot) const Center(child: CircularProgressIndicator()),
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isOnline) ...[
                                  _buildBookingActionCard(user.uid),
                                ],
                              ],
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 24,
                            child: Center(
                              child: ElevatedButton.icon(
                                onPressed: (_isToggling || loadingSnapshot) ? null : _toggleStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isOnline ? Colors.red : const Color(0xFF0066CC),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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