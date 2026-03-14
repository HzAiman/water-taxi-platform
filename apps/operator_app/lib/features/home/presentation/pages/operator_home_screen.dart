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
  static const MethodChannel _mapsConfigChannel = MethodChannel(
    'operator_app/maps_config',
  );

  bool _isOnline = false;
  bool _isToggling = false;
  bool _isUpdatingBooking = false;
  bool _hasLocationPermission = false;
  bool _hasShownWelcomeAlert = false;
  bool _hasCheckedMapsConfig = false;
  bool _mapReady = false;
  bool _isActiveSectionExpanded = false;
  bool _isQueueSectionExpanded = false;
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
      final operatorLabel =
          FirebaseAuth.instance.currentUser?.email ?? 'Operator';
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
      final result = await _mapsConfigChannel.invokeMapMethod<String, dynamic>(
        'getMapsConfigStatus',
      );
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
      showTopError(
        context,
        message: 'Unable to get current location: $e',
        title: 'Location error',
      );
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
          message:
              'Location permission was denied permanently. Enable it in Settings.',
          actionLabel: 'Open Settings',
          onAction: openAppSettings,
        );
      }
      setState(() => _hasLocationPermission = false);
      return false;
    }

    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (mounted) setState(() => _hasLocationPermission = granted);
    return granted;
  }

  Future<void> _centerOnUser() async {
    if (!_mapReady) {
      showTopInfo(
        context,
        message: 'Map is still loading.',
        title: 'Please wait',
      );
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
      showTopError(
        context,
        message: 'Unable to get location: $e',
        title: 'Location error',
      );
    }
  }

  Future<void> _toggleStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nextStatus = !_isOnline;
    final operatorRef = FirebaseFirestore.instance
        .collection('operators')
        .doc(user.uid);

    setState(() {
      _isToggling = true;
      _isOnline = nextStatus;
    });

    try {
      final operatorSnap = await operatorRef.get().timeout(
        const Duration(seconds: 6),
      );

      if (!operatorSnap.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message:
              'Operator profile is missing. Please complete profile setup again.',
        );
      }

      await operatorRef
          .update({
            'isOnline': nextStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 6));

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
        showTopError(
          context,
          message: 'Updating status timed out. Check your network.',
          title: 'Status update failed',
        );
      }
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('Operator status update failed [${e.code}]: ${e.message}');
      }

      if (!mounted) {
        return;
      }

      setState(() => _isOnline = !nextStatus);

      String message;
      switch (e.code) {
        case 'permission-denied':
          message =
              'Permission denied while updating operator status. Deploy latest Firestore rules and ensure this account has an operator profile.';
          break;
        case 'not-found':
          message =
              'Operator profile document was not found. Sign out and sign in again to trigger profile setup.';
          break;
        case 'unavailable':
          message =
              'Firestore is currently unavailable. Please check connection and try again.';
          break;
        default:
          message = e.message ?? 'Unexpected Firebase error (${e.code}).';
          break;
      }

      showTopError(context, message: message, title: 'Status update failed');
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = !nextStatus);
        showTopError(
          context,
          message: 'Failed to update status: $e',
          title: 'Status update failed',
        );
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
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': status,
            'driverId': driverId,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) {
        return;
      }

      showTopSuccess(
        context,
        message: 'Booking status updated to ${_formatStatusLabel(status)}.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      showTopError(
        context,
        message: 'Failed to update booking: $e',
        title: 'Booking update failed',
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingBooking = false);
      }
    }
  }

  Future<void> _acceptBookingAtomically({
    required String bookingId,
    required String userId,
  }) async {
    if (_isUpdatingBooking) {
      return;
    }

    setState(() => _isUpdatingBooking = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final bookingRef = FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId);
        final snapshot = await transaction.get(bookingRef);

        if (!snapshot.exists) {
          throw StateError('This booking no longer exists.');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        final driverId = (data['driverId'] ?? '').toString();
        final rejectedBy = _asStringList(data['rejectedBy']);

        if (status != 'pending') {
          throw StateError('This booking is no longer pending.');
        }

        if (driverId.isNotEmpty) {
          throw StateError(
            'This booking was already assigned to another operator.',
          );
        }

        if (rejectedBy.contains(userId)) {
          throw StateError('You already rejected this booking.');
        }

        transaction.update(bookingRef, {
          'status': 'accepted',
          'driverId': userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      showTopSuccess(context, message: 'Booking accepted successfully.');
    } on StateError catch (e) {
      if (!mounted) {
        return;
      }
      showTopInfo(
        context,
        title: 'Unable to accept booking',
        message: e.message.toString(),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopError(
        context,
        title: 'Accept failed',
        message: 'Could not accept booking: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingBooking = false);
      }
    }
  }

  Future<void> _rejectBooking({
    required String bookingId,
    required String userId,
  }) async {
    if (_isUpdatingBooking) {
      return;
    }

    setState(() => _isUpdatingBooking = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final bookingRef = FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId);
        final snapshot = await transaction.get(bookingRef);

        if (!snapshot.exists) {
          throw StateError('This booking no longer exists.');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        final driverId = (data['driverId'] ?? '').toString();
        final rejectedBy = _asStringList(data['rejectedBy']);

        if (status != 'pending' || driverId.isNotEmpty) {
          throw StateError('Only unassigned pending bookings can be rejected.');
        }

        if (rejectedBy.contains(userId)) {
          throw StateError('You already rejected this booking.');
        }

        transaction.update(bookingRef, {
          'rejectedBy': FieldValue.arrayUnion([userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) {
        return;
      }

      showTopInfo(
        context,
        title: 'Booking rejected',
        message: 'This booking stays pending and is hidden from your queue.',
      );
    } on StateError catch (e) {
      if (!mounted) {
        return;
      }
      showTopInfo(
        context,
        title: 'Unable to reject booking',
        message: e.message.toString(),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopError(
        context,
        title: 'Reject failed',
        message: 'Could not reject booking: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingBooking = false);
      }
    }
  }

  Widget _buildBookingActionCard(String userId) {
    final activeQuery = FirebaseFirestore.instance
        .collection('bookings')
        .where('driverId', isEqualTo: userId)
        .limit(50)
        .snapshots(includeMetadataChanges: true);

    final pendingQuery = FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: 'pending')
        .limit(100)
        .snapshots(includeMetadataChanges: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeQuery,
      builder: (context, activeSnapshot) {
        if (activeSnapshot.hasError) {
          return _buildInfoCard(
            icon: Icons.error_outline,
            iconColor: Colors.red,
            title: 'Unable to load active booking',
            subtitle: _describeStreamError(activeSnapshot.error),
          );
        }

        final activeDocs = (activeSnapshot.data?.docs ?? const []).where((doc) {
          final status = (doc.data()['status'] ?? '').toString().toLowerCase();
          return status == 'accepted' || status == 'on_the_way';
        }).toList();

        activeDocs.sort((a, b) {
          final aTs = a.data()['updatedAt'];
          final bTs = b.data()['updatedAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }
          return 0;
        });

        final activeDoc = activeDocs.isNotEmpty ? activeDocs.first : null;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: pendingQuery,
          builder: (context, pendingSnapshot) {
            if (pendingSnapshot.hasError) {
              return _buildInfoCard(
                icon: Icons.error_outline,
                iconColor: Colors.red,
                title: 'Unable to load booking queue',
                subtitle: _describeStreamError(pendingSnapshot.error),
              );
            }

            final allPendingDocs = pendingSnapshot.data?.docs ?? const [];
            final pendingDocs = allPendingDocs.where((doc) {
              final driverId = (doc.data()['driverId'] ?? '').toString();
              if (driverId.isNotEmpty) {
                return false;
              }
              final rejectedBy = _asStringList(doc.data()['rejectedBy']);
              return !rejectedBy.contains(userId);
            }).toList();

            pendingDocs.sort((a, b) {
              final aTs = a.data()['createdAt'];
              final bTs = b.data()['createdAt'];
              if (aTs is Timestamp && bTs is Timestamp) {
                return aTs.compareTo(bTs);
              }
              return 0;
            });

            final topPendingDoc = pendingDocs.isNotEmpty
                ? pendingDocs.first
                : null;
            final pendingCount = pendingDocs.length;
            final activeCount = activeDoc == null ? 0 : 1;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatsCard(
                  pendingCount: pendingCount,
                  activeCount: activeCount,
                  isQueueExpanded: _isQueueSectionExpanded,
                  isActiveExpanded: _isActiveSectionExpanded,
                  onPendingTap: () {
                    setState(() {
                      final shouldExpand = !_isQueueSectionExpanded;
                      _isQueueSectionExpanded = shouldExpand;
                      _isActiveSectionExpanded = false;
                    });
                  },
                  onActiveTap: () {
                    setState(() {
                      final shouldExpand = !_isActiveSectionExpanded;
                      _isActiveSectionExpanded = shouldExpand;
                      _isQueueSectionExpanded = false;
                    });
                  },
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: activeDoc != null
                        ? _buildActiveBookingCard(activeDoc, userId)
                        : _buildInfoCard(
                            icon: Icons.directions_boat_filled_outlined,
                            iconColor: const Color(0xFF0066CC),
                            title: 'No active trip',
                            subtitle:
                                'Accept a booking from the queue to start operating.',
                          ),
                  ),
                  crossFadeState: _isActiveSectionExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: topPendingDoc != null
                        ? _buildPendingBookingCard(
                            topPendingDoc,
                            userId,
                            pendingCount,
                          )
                        : _buildInfoCard(
                            icon: Icons.hourglass_top,
                            iconColor: Colors.orange,
                            title: 'No pending bookings',
                            subtitle:
                                'You are online. Waiting for passengers...',
                          ),
                  ),
                  crossFadeState: _isQueueSectionExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStatsCard({
    required int pendingCount,
    required int activeCount,
    required bool isQueueExpanded,
    required bool isActiveExpanded,
    required VoidCallback onPendingTap,
    required VoidCallback onActiveTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatTile(
              label: 'Pending Queue',
              value: pendingCount.toString(),
              color: Colors.orange,
              isExpanded: isQueueExpanded,
              onTap: onPendingTap,
            ),
          ),
          Container(width: 1, height: 36, color: Colors.grey[300]),
          Expanded(
            child: _buildStatTile(
              label: 'Active Trip',
              value: activeCount.toString(),
              color: const Color(0xFF0066CC),
              isExpanded: isActiveExpanded,
              onTap: onActiveTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required Color color,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.grey[700],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBookingCard(
    DocumentSnapshot<Map<String, dynamic>> bookingDoc,
    String userId,
  ) {
    final booking = bookingDoc.data() ?? <String, dynamic>{};
    final status = (booking['status'] ?? 'accepted').toString().toLowerCase();
    final actionLabel = status == 'accepted' ? 'Start Trip' : 'Complete Trip';
    final nextStatus = status == 'accepted' ? 'on_the_way' : 'completed';
    final actionColor = status == 'accepted'
        ? const Color(0xFF0066CC)
        : Colors.green;

    return _buildInfoCard(
      icon: status == 'accepted' ? Icons.directions_boat : Icons.route,
      iconColor: actionColor,
      title: 'Current Booking: ${_formatStatusLabel(status)}',
      subtitle: _buildBookingDetailText(bookingDoc.id, booking),
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

  Widget _buildPendingBookingCard(
    DocumentSnapshot<Map<String, dynamic>> bookingDoc,
    String userId,
    int pendingCount,
  ) {
    final booking = bookingDoc.data() ?? <String, dynamic>{};
    return _buildInfoCard(
      icon: Icons.notifications_active,
      iconColor: Colors.orange,
      title: pendingCount > 1
          ? 'Next Pending Booking ($pendingCount in queue)'
          : 'Next Pending Booking',
      subtitle: _buildBookingDetailText(bookingDoc.id, booking),
      actionLabel: 'Accept Booking',
      actionColor: const Color(0xFF0066CC),
      secondaryActionLabel: 'Reject',
      secondaryActionColor: Colors.orange.shade50,
      secondaryActionTextColor: Colors.orange.shade900,
      onAction: _isUpdatingBooking
          ? null
          : () => _acceptBookingAtomically(
              bookingId: bookingDoc.id,
              userId: userId,
            ),
      onSecondaryAction: _isUpdatingBooking
          ? null
          : () => _rejectBooking(bookingId: bookingDoc.id, userId: userId),
    );
  }

  String _buildBookingDetailText(
    String bookingId,
    Map<String, dynamic> booking,
  ) {
    final origin = (booking['origin'] ?? 'Unknown').toString();
    final destination = (booking['destination'] ?? 'Unknown').toString();
    final passengerCount = _toInt(booking['passengerCount']) ?? 1;
    final fareRaw = booking['totalFare'] ?? booking['fare'];
    final fareValue = fareRaw is num
        ? fareRaw.toDouble()
        : double.tryParse(fareRaw?.toString() ?? '');
    final createdAt = booking['createdAt'];
    final createdLabel = _formatTimestamp(createdAt);

    return 'Booking ID: $bookingId\n'
        'Route: $origin -> $destination\n'
        'Passengers: $passengerCount\n'
        'Fare: ${fareValue == null ? 'N/A' : _formatCurrency(fareValue)}\n'
        'Created: $createdLabel';
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? actionLabel,
    String? secondaryActionLabel,
    Color actionColor = const Color(0xFF0066CC),
    Color secondaryActionColor = const Color(0xFFF3F4F6),
    Color secondaryActionTextColor = const Color(0xFF1F2937),
    VoidCallback? onAction,
    VoidCallback? onSecondaryAction,
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
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (secondaryActionLabel != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondaryAction,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: secondaryActionColor,
                        foregroundColor: secondaryActionTextColor,
                        side: BorderSide(
                          color: secondaryActionTextColor.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Text(secondaryActionLabel),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(actionLabel),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static List<String> _asStringList(dynamic value) {
    if (value is Iterable) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static String _formatCurrency(double value) {
    return 'RM ${value.toStringAsFixed(2)}';
  }

  static String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) {
      return 'Unknown';
    }
    final dt = value.toDate().toLocal();
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/${dt.year} $hour:$minute';
  }

  static String _describeStreamError(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'failed-precondition') {
        return 'Firestore query needs an index (failed-precondition). Deploy indexes or use fallback query.';
      }
      return 'Firestore error (${error.code}): ${error.message ?? 'Unknown error'}';
    }
    return 'Please check your connection and try again.';
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
      appBar: AppBar(toolbarHeight: 0, elevation: 0),
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
                    stream: FirebaseFirestore.instance
                        .collection('operators')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data();
                      if (data != null &&
                          data['isOnline'] is bool &&
                          !_isToggling) {
                        _isOnline = data['isOnline'] as bool;
                      }

                      final loadingSnapshot =
                          snapshot.connectionState == ConnectionState.waiting;
                      final buttonLabel = _isOnline
                          ? 'Go Offline'
                          : 'Go Online';

                      return Stack(
                        children: [
                          if (loadingSnapshot)
                            const Center(child: CircularProgressIndicator()),
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isOnline) ...[
                                  _buildBookingActionCard(user.uid),
                                ] else ...[
                                  _buildInfoCard(
                                    icon: Icons.power_settings_new,
                                    iconColor: Colors.red,
                                    title: 'You are offline',
                                    subtitle:
                                        'Go online to view active trips and pending booking queue.',
                                  ),
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
                                onPressed: (_isToggling || loadingSnapshot)
                                    ? null
                                    : _toggleStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isOnline
                                      ? Colors.red
                                      : const Color(0xFF0066CC),
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
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
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
