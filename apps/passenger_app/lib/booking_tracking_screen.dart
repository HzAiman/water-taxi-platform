import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class BookingTrackingScreen extends StatefulWidget {
  final String bookingId;
  final String origin;
  final String destination;
  final int passengerCount;

  const BookingTrackingScreen({
    super.key,
    required this.bookingId,
    required this.origin,
    required this.destination,
    required this.passengerCount,
  });

  @override
  State<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends State<BookingTrackingScreen> {
  bool _isCancelling = false;

  void _closeTrackingScreen() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _cancelBooking() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: const Text('Are you sure you want to cancel this booking?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Booking'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancel Booking'),
            ),
          ],
        );
      },
    );

    if (shouldCancel != true || !mounted) {
      return;
    }

    setState(() {
      _isCancelling = true;
    });

    try {
      await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled successfully.'),
          backgroundColor: Color(0xFF0066CC),
        ),
      );

      _closeTrackingScreen();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel booking: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Status'),
        centerTitle: true,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildMessageState(
              title: 'Unable to load booking',
              message: 'Please check your connection and try again.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final bookingDoc = snapshot.data;
          if (bookingDoc == null || !bookingDoc.exists) {
            return _buildMessageState(
              title: 'Booking not found',
              message: 'This booking may have been deleted or is unavailable.',
            );
          }

          final booking = bookingDoc.data() ?? <String, dynamic>{};
          final currentOrigin = (booking['origin'] ?? widget.origin).toString();
          final currentDestination = (booking['destination'] ?? widget.destination).toString();
          final currentPassengerCount = _toInt(booking['passengerCount']) ?? widget.passengerCount;
          final status = (booking['status'] ?? 'pending').toString();
          final paymentMethod = (booking['paymentMethod'] ?? 'unknown').toString();
          final paymentStatus = (booking['paymentStatus'] ?? 'unknown').toString();
          final statusTheme = _statusThemeFor(status);
          final canCancel = _canCancelStatus(status);

          final originPoint = _geoPointToLatLng(booking['originCoords']);
          final destinationPoint = _geoPointToLatLng(booking['destinationCoords']);
          final markers = _buildMarkers(
            originPoint: originPoint,
            destinationPoint: destinationPoint,
            originLabel: currentOrigin,
            destinationLabel: currentDestination,
          );
          final polylines = _buildPolylines(originPoint, destinationPoint);

          return Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: _cameraPositionFor(originPoint, destinationPoint),
                  markers: markers,
                  polylines: polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  compassEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              DraggableScrollableSheet(
                initialChildSize: 0.30,
                minChildSize: 0.22,
                maxChildSize: 0.66,
                snap: true,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 12,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDE5F0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: statusTheme.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  statusTheme.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            statusTheme.message,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF666666),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text(
                                'Booking ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.bookingId,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F5FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFDDE5F0)),
                            ),
                            child: Column(
                              children: [
                                _buildLocationRow(Icons.location_on, 'Pick-up', currentOrigin),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Divider(color: Color(0xFFDDE5F0)),
                                ),
                                _buildLocationRow(Icons.flag, 'Drop-off', currentDestination),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.people,
                                  label: 'Passengers',
                                  value: '$currentPassengerCount ${currentPassengerCount == 1 ? 'Passenger' : 'Passengers'}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.account_balance_wallet,
                                  label: 'Payment',
                                  value: '${_formatPaymentMethod(paymentMethod)} • ${_formatStatusLabel(paymentStatus)}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canCancel ? const Color(0xFFD64545) : const Color(0xFF0066CC),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _isCancelling
                                  ? null
                                  : canCancel
                                      ? _cancelBooking
                                    : _closeTrackingScreen,
                              child: _isCancelling
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Text(canCancel ? 'Cancel Booking' : 'Close'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static const CameraPosition _fallbackCameraPosition = CameraPosition(
    target: LatLng(2.1916, 102.2490),
    zoom: 14,
  );

  Widget _buildMessageState({required String title, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 56, color: Color(0xFF0066CC)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF0066CC), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                address,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0066CC), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CameraPosition _cameraPositionFor(LatLng? originPoint, LatLng? destinationPoint) {
    if (originPoint != null && destinationPoint != null) {
      return CameraPosition(
        target: LatLng(
          (originPoint.latitude + destinationPoint.latitude) / 2,
          (originPoint.longitude + destinationPoint.longitude) / 2,
        ),
        zoom: 14,
      );
    }

    if (originPoint != null) {
      return CameraPosition(target: originPoint, zoom: 16);
    }

    if (destinationPoint != null) {
      return CameraPosition(target: destinationPoint, zoom: 16);
    }

    return _fallbackCameraPosition;
  }

  Set<Marker> _buildMarkers({
    required LatLng? originPoint,
    required LatLng? destinationPoint,
    required String originLabel,
    required String destinationLabel,
  }) {
    final markers = <Marker>{};

    if (originPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: originPoint,
          infoWindow: InfoWindow(title: 'Pick-up', snippet: originLabel),
        ),
      );
    }

    if (destinationPoint != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPoint,
          infoWindow: InfoWindow(title: 'Drop-off', snippet: destinationLabel),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines(LatLng? originPoint, LatLng? destinationPoint) {
    if (originPoint == null || destinationPoint == null) {
      return const <Polyline>{};
    }

    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [originPoint, destinationPoint],
        color: const Color(0xFF0066CC),
        width: 4,
      ),
    };
  }

  LatLng? _geoPointToLatLng(dynamic value) {
    if (value is GeoPoint) {
      return LatLng(value.latitude, value.longitude);
    }
    return null;
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _formatPaymentMethod(String paymentMethod) {
    switch (paymentMethod) {
      case 'credit_card':
        return 'Card';
      case 'e_wallet':
        return 'E-Wallet';
      case 'online_banking':
        return 'Online Banking';
      default:
        return _formatStatusLabel(paymentMethod);
    }
  }

  String _formatStatusLabel(String status) {
    return status
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _canCancelStatus(String status) {
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

  _BookingStatusTheme _statusThemeFor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const _BookingStatusTheme(
          title: 'Booking Request Pending',
          message: 'Waiting for an operator to accept your booking request.',
          color: Colors.orange,
        );
      case 'confirmed':
      case 'accepted':
        return const _BookingStatusTheme(
          title: 'Booking Confirmed',
          message: 'An operator has accepted your booking.',
          color: Color(0xFF0066CC),
        );
      case 'on_the_way':
      case 'in_progress':
      case 'ongoing':
        return const _BookingStatusTheme(
          title: 'Trip In Progress',
          message: 'Your assigned operator is currently handling this trip.',
          color: Colors.teal,
        );
      case 'completed':
        return const _BookingStatusTheme(
          title: 'Trip Completed',
          message: 'This booking has been completed successfully.',
          color: Colors.green,
        );
      case 'cancelled':
        return const _BookingStatusTheme(
          title: 'Booking Cancelled',
          message: 'This booking was cancelled.',
          color: Colors.red,
        );
      default:
        return _BookingStatusTheme(
          title: 'Status: ${_formatStatusLabel(status)}',
          message: 'This booking has been updated.',
          color: const Color(0xFF0066CC),
        );
    }
  }
}

class _BookingStatusTheme {
  final String title;
  final String message;
  final Color color;

  const _BookingStatusTheme({
    required this.title,
    required this.message,
    required this.color,
  });
}
