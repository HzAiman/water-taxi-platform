import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:passenger_app/booking_tracking_screen.dart';

class PaymentScreen extends StatefulWidget {
  final String origin;
  final String destination;
  final int adultCount;
  final int childCount;

  const PaymentScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.adultCount,
    required this.childCount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isProcessing = false;
  String? _selectedPaymentMethod;
  bool _isLoadingFare = true;
  String? _fareError;
  Map<String, double>? _fareDetails;

  @override
  void initState() {
    super.initState();
    _loadFare();
  }

  // Load fare from Firestore
  Future<void> _loadFare() async {
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('fares')
          .where('origin', isEqualTo: widget.origin)
          .where('destination', isEqualTo: widget.destination)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          setState(() {
            _fareError = 'Fare not found for this route';
            _isLoadingFare = false;
          });
        }
        return;
      }

      final fareDoc = snapshot.docs.first;
      double adultFarePerPerson = (fareDoc['adultFare'] ?? 0.0).toDouble();
      double childFarePerPerson = (fareDoc['childFare'] ?? 0.0).toDouble();

      double adultTotal = adultFarePerPerson * widget.adultCount;
      double childTotal = childFarePerPerson * widget.childCount;
      double total = adultTotal + childTotal;

      if (mounted) {
        setState(() {
          _fareDetails = {
            'adultPerPerson': adultFarePerPerson,
            'childPerPerson': childFarePerPerson,
            'adultTotal': adultTotal,
            'childTotal': childTotal,
            'total': total,
          };
          _isLoadingFare = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fareError = 'Failed to load fare information';
          _isLoadingFare = false;
        });
      }
    }
  }

  Future<void> _processPayment() async {
    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a payment method'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    // Simulate payment processing
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
    });

    // Navigate to booking tracking screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => BookingTrackingScreen(
          origin: widget.origin,
          destination: widget.destination,
          passengerCount: widget.adultCount + widget.childCount,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment"),
        centerTitle: true,
      ),
      body: _isLoadingFare
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading fare information...'),
                ],
              ),
            )
          : _fareError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _fareError!,
                        style: const TextStyle(fontSize: 16, color: Colors.red),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trip Summary Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5FF),
                border: Border(
                  bottom: BorderSide(color: const Color(0xFFDDE5F0), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Trip Summary",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // From
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFF0066CC),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Pick-up",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF666666),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              widget.origin,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // To
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.flag,
                        color: Color(0xFF0066CC),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Drop-off",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF666666),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              widget.destination,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Passengers
                  Row(
                    children: [
                      const Icon(
                        Icons.people,
                        color: Color(0xFF0066CC),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Passengers",
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            "${widget.adultCount} Adult${widget.adultCount > 1 ? 's' : ''}, ${widget.childCount} Child${widget.childCount != 1 ? 'ren' : ''}",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Fare Details Section
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Fare Details",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFDDE5F0),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Adult Fare
                        if (widget.adultCount > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Adult Fare (x${widget.adultCount})",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF666666),
                                ),
                              ),
                              Text(
                                "RM ${_fareDetails!['adultPerPerson']!.toStringAsFixed(2)} × ${widget.adultCount}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Adult Subtotal",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1A1A1A),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                "RM ${_fareDetails!['adultTotal']!.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.adultCount > 0 && widget.childCount > 0)
                          const SizedBox(height: 12),
                        // Child Fare
                        if (widget.childCount > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Child Fare (x${widget.childCount})",
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF666666),
                                ),
                              ),
                              Text(
                                "RM ${_fareDetails!['childPerPerson']!.toStringAsFixed(2)} × ${widget.childCount}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Child Subtotal",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1A1A1A),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                "RM ${_fareDetails!['childTotal']!.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(color: Color(0xFFDDE5F0), height: 1),
                        const SizedBox(height: 12),
                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Total Fare",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              "RM ${_fareDetails!['total']!.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0066CC),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Payment Method Selection
                  const Text(
                    "Payment Method",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPaymentMethodOption(
                    "credit_card",
                    "Credit / Debit Card",
                    Icons.credit_card,
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentMethodOption(
                    "e_wallet",
                    "E-Wallet",
                    Icons.account_balance_wallet,
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentMethodOption(
                    "online_banking",
                    "Online Banking",
                    Icons.account_balance,
                  ),
                  const SizedBox(height: 32),

                  // Pay Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _processPayment,
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              "Pay RM ${_fareDetails!['total']!.toStringAsFixed(2)}",
                              style: const TextStyle(
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
    );
  }

  Widget _buildPaymentMethodOption(
    String value,
    String label,
    IconData icon,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedPaymentMethod == value
                ? const Color(0xFF0066CC)
                : const Color(0xFFDDE5F0),
            width: _selectedPaymentMethod == value ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: _selectedPaymentMethod == value
                  ? const Color(0xFF0066CC)
                  : const Color(0xFF666666),
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _selectedPaymentMethod == value
                      ? const Color(0xFF0066CC)
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (_selectedPaymentMethod == value)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF0066CC),
                size: 24,
              )
            else
              const Icon(
                Icons.radio_button_unchecked,
                color: Color(0xFFDDE5F0),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
