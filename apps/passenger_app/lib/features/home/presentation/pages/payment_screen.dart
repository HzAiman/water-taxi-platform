import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/data/repositories/booking_repository.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/booking_tracking_view_model.dart';
import 'package:passenger_app/features/home/presentation/viewmodels/payment_view_model.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.adultCount,
    required this.childCount,
  });

  final String origin;
  final String destination;
  final int adultCount;
  final int childCount;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      context.read<PaymentViewModel>().loadFare(
        origin: widget.origin,
        destination: widget.destination,
        adultCount: widget.adultCount,
        childCount: widget.childCount,
      );
    });
  }

  Future<void> _processPayment() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      showTopError(context, message: 'User not authenticated.');
      return;
    }

    final viewModel = context.read<PaymentViewModel>();
    final result = await viewModel.processPayment(
      userId: currentUser.uid,
      origin: widget.origin,
      destination: widget.destination,
      adultCount: widget.adultCount,
      childCount: widget.childCount,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case OperationSuccess(:final message):
        final bookingRepo = context.read<BookingRepository>();
        final passengerCount = widget.adultCount + widget.childCount;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => BookingTrackingViewModel(bookingRepo: bookingRepo),
              child: BookingTrackingScreen(
                bookingId: message,
                origin: widget.origin,
                destination: widget.destination,
                passengerCount: passengerCount,
              ),
            ),
          ),
          (route) => route.isFirst,
        );
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<PaymentViewModel>();
    final fare = viewModel.fareBreakdown;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment'), centerTitle: true),
      body: viewModel.isLoadingFare
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
          : viewModel.fareError != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    viewModel.fareError!,
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
          : fare == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F5FF),
                      border: Border(
                        bottom: BorderSide(
                          color: const Color(0xFFDDE5F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 16),
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
                                    'Pick-up',
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
                                    'Drop-off',
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
                                  'Passengers',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF666666),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${widget.adultCount} Adult${widget.adultCount > 1 ? 's' : ''}, ${widget.childCount} Child${widget.childCount != 1 ? 'ren' : ''}',
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
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fare Details',
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
                              if (widget.adultCount > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Adult Fare (x${widget.adultCount})',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                    Text(
                                      'RM ${fare.adultFarePerPerson.toStringAsFixed(2)} × ${widget.adultCount}',
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Adult Subtotal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF1A1A1A),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'RM ${fare.adultSubtotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (widget.adultCount > 0 &&
                                  widget.childCount > 0)
                                const SizedBox(height: 12),
                              if (widget.childCount > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Child Fare (x${widget.childCount})',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                    Text(
                                      'RM ${fare.childFarePerPerson.toStringAsFixed(2)} × ${widget.childCount}',
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Child Subtotal',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF1A1A1A),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'RM ${fare.childSubtotal.toStringAsFixed(2)}',
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
                              const Divider(
                                color: Color(0xFFDDE5F0),
                                height: 1,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Fare',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  Text(
                                    'RM ${fare.total.toStringAsFixed(2)}',
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
                        const Text(
                          'Payment Method',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPaymentMethodOption(
                          context,
                          PaymentMethods.creditCard,
                          PaymentMethods.label(PaymentMethods.creditCard),
                          Icons.credit_card,
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentMethodOption(
                          context,
                          PaymentMethods.eWallet,
                          PaymentMethods.label(PaymentMethods.eWallet),
                          Icons.account_balance_wallet,
                        ),
                        const SizedBox(height: 12),
                        _buildPaymentMethodOption(
                          context,
                          PaymentMethods.onlineBanking,
                          PaymentMethods.label(PaymentMethods.onlineBanking),
                          Icons.account_balance,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: viewModel.isProcessing
                                ? null
                                : _processPayment,
                            child: viewModel.isProcessing
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Pay RM ${fare.total.toStringAsFixed(2)}',
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
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    final selectedValue = context
        .watch<PaymentViewModel>()
        .selectedPaymentMethod;

    return GestureDetector(
      onTap: () => context.read<PaymentViewModel>().selectPaymentMethod(value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedValue == value
                ? const Color(0xFF0066CC)
                : const Color(0xFFDDE5F0),
            width: selectedValue == value ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selectedValue == value
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
                  color: selectedValue == value
                      ? const Color(0xFF0066CC)
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (selectedValue == value)
              const Icon(Icons.check_circle, color: Color(0xFF0066CC), size: 24)
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
