import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/features/auth/presentation/pages/phone_login_page.dart';
import 'package:passenger_app/features/home/presentation/pages/booking_tracking_screen.dart';
import 'package:passenger_app/features/profile/presentation/viewmodels/profile_view_model.dart';
import 'package:provider/provider.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.testUserId,
    this.testPhoneNumber,
  });

  final String? testUserId;
  final String? testPhoneNumber;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _hasInitialized = false;

  String? get _effectiveUserId =>
      widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized) {
      return;
    }

    _hasInitialized = true;
    final uid = _effectiveUserId;
    if (uid != null) {
      Future.microtask(() {
        if (!mounted) {
          return;
        }
        context.read<ProfileViewModel>().loadProfile(uid);
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !context.mounted) {
      return;
    }

    await FirebaseAuth.instance.signOut();

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginPage()),
      (route) => false,
    );
  }

  Widget _buildMainProfileMenu() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildMenuButton(
          icon: Icons.manage_accounts,
          title: 'Account Management',
          subtitle: 'Update your profile details and manage account',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _AccountManagementRoutePage(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildMenuButton(
          icon: Icons.receipt_long,
          title: 'Booking History',
          subtitle: 'View your recent and past bookings',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _BookingHistoryRoutePage(
                  testUserId: widget.testUserId,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red, width: 1.5),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE5F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0066CC)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF7A8AA0)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final viewModel = context.watch<ProfileViewModel>();
    final user = viewModel.user;
    final phoneNumber = widget.testPhoneNumber ??
      FirebaseAuth.instance.currentUser?.phoneNumber ??
      user?.phoneNumber ??
      '';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0xFF0066CC),
      ),
      child: Scaffold(
        body: Column(
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
                    Text(
                      user?.name.isNotEmpty == true ? user!.name : 'Passenger',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phoneNumber,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: viewModel.isLoading && user == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMainProfileMenu(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountManagementRoutePage extends StatefulWidget {
  const _AccountManagementRoutePage();

  @override
  State<_AccountManagementRoutePage> createState() =>
      _AccountManagementRoutePageState();
}

class _AccountManagementRoutePageState
    extends State<_AccountManagementRoutePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final TextEditingController _phoneController = TextEditingController();

  String _phoneNumber = '';
  bool _isEditing = false;
  bool _hasLoadedInitialData = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }

  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) {
      return;
    }

    _phoneNumber = currentUser.phoneNumber ?? '';
    _phoneController.text = _phoneNumber;

    await context.read<ProfileViewModel>().loadProfile(currentUser.uid);
    if (!mounted) {
      return;
    }

    final user = context.read<ProfileViewModel>().user;
    if (user != null) {
      _nameController.text = user.name;
      _emailController.text = user.email.isNotEmpty
          ? user.email
          : currentUser.email ?? '';
    } else {
      _emailController.text = currentUser.email ?? '';
    }

    if (!_hasLoadedInitialData) {
      setState(() {
        _hasLoadedInitialData = true;
      });
    }
  }

  void _resetFormFromViewModel() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final user = context.read<ProfileViewModel>().user;

    _nameController.text = user?.name ?? '';
    _emailController.text = user?.email.isNotEmpty == true
        ? user!.email
        : currentUser?.email ?? '';
    _phoneController.text = _phoneNumber;
  }

  Future<void> _saveUserData() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      showTopError(context, message: 'User not authenticated.');
      return;
    }

    final nextEmail = _emailController.text.trim();
    final previousEmail = currentUser.email ?? '';
    final result = await context.read<ProfileViewModel>().updateProfile(
      uid: currentUser.uid,
      name: _nameController.text.trim(),
      email: nextEmail,
    );

    if (!mounted) {
      return;
    }

    switch (result) {
      case OperationSuccess():
        if (nextEmail.isNotEmpty && nextEmail != previousEmail) {
          try {
            await currentUser.verifyBeforeUpdateEmail(nextEmail);
          } catch (e) {
            if (!mounted) {
              return;
            }
            showTopInfo(
              context,
              title: 'Profile updated',
              message:
                  'Profile data was saved, but email verification could not be started: $e',
            );
            setState(() {
              _isEditing = false;
            });
            return;
          }

          if (!mounted) {
            return;
          }
        }

        setState(() {
          _isEditing = false;
        });
        showTopSuccess(
          context,
          message: nextEmail != previousEmail && nextEmail.isNotEmpty
              ? 'Profile updated. Check your email to confirm the new address.'
              : 'Profile updated successfully.',
        );
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  Future<void> _deleteAccount() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'This action cannot be undone. Your profile and login access will be deleted. Booking records may be retained for operational and financial auditing. Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      showTopError(context, message: 'User not authenticated.');
      return;
    }

    try {
      await currentUser.delete();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      final needsRecentLogin =
          e.code == 'requires-recent-login' ||
          e.code == 'user-token-expired' ||
          e.code == 'invalid-user-token';

      if (needsRecentLogin) {
        final shouldReauthenticate = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Reauthentication required'),
              content: const Text(
                'For security, please log in again before deleting your account.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Re-login'),
                ),
              ],
            );
          },
        );

        if (shouldReauthenticate == true) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) {
            return;
          }
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const PhoneLoginPage()),
            (route) => false,
          );
        }
        return;
      }

      showTopError(context, message: 'Error deleting account: ${e.message}');
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }
      showTopError(context, message: 'Error deleting account: $e');
      return;
    }

    final result = await context.read<ProfileViewModel>().deleteAccount(
      currentUser.uid,
    );
    if (!mounted) {
      return;
    }

    if (result case OperationFailure(:final title, :final message, :final isInfo)) {
      if (isInfo) {
        showTopInfo(context, title: title, message: message);
      } else {
        showTopError(context, title: title, message: message);
      }
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneLoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProfileViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
        centerTitle: true,
      ),
      body: !_hasLoadedInitialData && viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Full Name',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          hintText: 'Enter your full name',
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (_isEditing &&
                              (value == null || value.trim().isEmpty)) {
                            return 'Name cannot be empty';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Email Address',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        enabled: _isEditing,
                        decoration: const InputDecoration(
                          hintText: 'Enter your email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) {
                          if (_isEditing) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Email cannot be empty';
                            }
                            if (!RegExp(
                              r'^[^@]+@[^@]+\.[^@]+',
                            ).hasMatch(value)) {
                              return 'Enter a valid email address';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Phone Number',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneController,
                        enabled: false,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.phone),
                          hintText: 'Phone number',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Phone number is managed by your login account and cannot be changed here.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (!_isEditing)
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isEditing = true;
                              });
                            },
                            child: const Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: viewModel.isSaving
                                    ? null
                                    : _saveUserData,
                                child: viewModel.isSaving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: OutlinedButton(
                                onPressed: viewModel.isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          _isEditing = false;
                                        });
                                        _resetFormFromViewModel();
                                      },
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0066CC),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: viewModel.isSaving ? null : _deleteAccount,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                          ),
                          child: viewModel.isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.red,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Delete Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.red,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

enum _BookingHistoryFilter { all, active, completed, cancelled }

class _BookingHistoryRoutePage extends StatefulWidget {
  const _BookingHistoryRoutePage({this.testUserId});

  final String? testUserId;

  @override
  State<_BookingHistoryRoutePage> createState() =>
      _BookingHistoryRoutePageState();
}

class _BookingHistoryRoutePageState extends State<_BookingHistoryRoutePage> {
  _BookingHistoryFilter _selectedFilter = _BookingHistoryFilter.all;
  bool _hasStartedStream = false;
  ProfileViewModel? _profileViewModel;

  String? get _effectiveUserId =>
      widget.testUserId ?? FirebaseAuth.instance.currentUser?.uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStartedStream) {
      return;
    }

    final uid = _effectiveUserId;
    if (uid == null) {
      return;
    }

    _profileViewModel = context.read<ProfileViewModel>();
    _hasStartedStream = true;
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      _profileViewModel?.startBookingHistoryStream(uid);
    });
  }

  @override
  void dispose() {
    _profileViewModel?.stopBookingHistoryStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final hasUser = widget.testUserId != null || currentUser != null;
    final viewModel = context.watch<ProfileViewModel>();
    final bookings = viewModel.bookingHistory;

    return Scaffold(
      appBar: AppBar(title: const Text('Booking History'), centerTitle: true),
      body: hasUser
          ? _buildContent(viewModel, bookings)
          : const Center(child: Text('Please sign in to view your bookings.')),
    );
  }

  Widget _buildContent(ProfileViewModel viewModel, List<BookingModel> bookings) {
    if (viewModel.historyError != null) {
      return _buildHistoryState(
        icon: Icons.wifi_off,
        title: 'Unable to load booking history',
        message: viewModel.historyError!,
        actionLabel: 'Retry',
        onAction: viewModel.retryBookingHistoryStream,
      );
    }

    if (viewModel.isHistoryLoading && bookings.isEmpty) {
      return _buildHistoryState(
        icon: Icons.sync,
        title: 'Syncing your bookings',
        message: 'Please wait while we load your latest booking history.',
      );
    }

    if (bookings.isEmpty) {
      return _buildHistoryState(
        icon: Icons.directions_boat,
        title: 'No bookings yet',
        message:
            'Your completed and upcoming water taxi bookings will appear here.',
      );
    }

    final filteredBookings = bookings.where((booking) {
      switch (_selectedFilter) {
        case _BookingHistoryFilter.active:
          return booking.status.isActive;
        case _BookingHistoryFilter.completed:
          return booking.status == BookingStatus.completed;
        case _BookingHistoryFilter.cancelled:
          return booking.status == BookingStatus.cancelled ||
              booking.status == BookingStatus.rejected;
        case _BookingHistoryFilter.all:
          return true;
      }
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildFilterChips(),
        const SizedBox(height: 16),
        if (filteredBookings.isEmpty)
          _buildHistoryState(
            icon: Icons.filter_list,
            title: 'No ${_filterLabel(_selectedFilter).toLowerCase()} bookings',
            message: 'Try a different filter to see other bookings.',
          )
        else
          ...filteredBookings.map(_buildBookingCard),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _BookingHistoryFilter.values.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_filterLabel(filter)),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => setState(() => _selectedFilter = filter),
              selectedColor: const Color(0xFF0066CC).withValues(alpha: 0.15),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFF0066CC)
                    : const Color(0xFFDDE5F0),
              ),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFF0066CC)
                    : const Color(0xFF555555),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _filterLabel(_BookingHistoryFilter filter) {
    switch (filter) {
      case _BookingHistoryFilter.all:
        return 'All';
      case _BookingHistoryFilter.active:
        return 'Active';
      case _BookingHistoryFilter.completed:
        return 'Completed';
      case _BookingHistoryFilter.cancelled:
        return 'Cancelled';
    }
  }

  static Widget _buildHistoryState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE5F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: const Color(0xFF0066CC)),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingCard(BookingModel booking) {
    final totalFare = booking.totalFare > 0 ? booking.totalFare : booking.fare;
    final statusColor = _statusColor(booking.status);
    final paymentMethod = PaymentMethods.label(booking.paymentMethod);
    final paymentStatusLabel = _formatStatusLabel(booking.paymentStatus);
    final paymentOutcomeMessage = _historyPaymentOutcomeMessage(booking);
    final createdAt = _formatTimestamp(booking.createdAt);
    final bookingTitle = booking.bookingId.isNotEmpty
        ? booking.bookingId
        : 'Booking';
    final showStaleAction =
      booking.status.isActive &&
      booking.updatedAt != null &&
      DateTime.now().difference(booking.updatedAt!) >
        const Duration(minutes: 5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bookingTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatStatusLabel(booking.status.firestoreValue),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHistoryRow(
            Icons.location_on,
            'Route',
            '${booking.origin} -> ${booking.destination}',
          ),
          const SizedBox(height: 8),
          _buildHistoryRow(
            Icons.people,
            'Passengers',
            '${booking.passengerCount}',
          ),
          const SizedBox(height: 8),
          _buildHistoryRow(
            Icons.account_balance_wallet,
            'Payment',
            '$paymentMethod • $paymentStatusLabel',
          ),
          if (paymentOutcomeMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD7AE)),
              ),
              child: Text(
                paymentOutcomeMessage,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8A4B08),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _buildHistoryRow(Icons.schedule, 'Booked At', createdAt),
          const SizedBox(height: 12),
          if (showStaleAction) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFD9FF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Color(0xFF0066CC)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This active booking looks stale. Open live tracking to sync latest status.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0E4A8A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openTrackingFromHistory(booking),
                icon: const Icon(Icons.map),
                label: const Text('Open Live Tracking'),
              ),
            ),
          ],
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Fare',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'RM ${totalFare.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF0066CC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openTrackingFromHistory(BookingModel booking) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingTrackingScreen(
          bookingId: booking.bookingId,
          origin: booking.origin,
          destination: booking.destination,
          passengerCount: booking.passengerCount,
        ),
      ),
    );
  }

  static Widget _buildHistoryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0066CC)),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                  ),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return 'Unavailable';
    }

    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  static String _formatStatusLabel(String status) {
    return status
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String? _historyPaymentOutcomeMessage(BookingModel booking) {
    final normalizedPayment = booking.paymentStatus.trim().toLowerCase();

    if (booking.status == BookingStatus.rejected) {
      if (normalizedPayment.contains('refunded')) {
        return 'Payment refunded successfully for this rejected booking.';
      }
      if (normalizedPayment.contains('cancelled')) {
        return 'Payment authorization released. No charge captured for this rejected booking.';
      }
      if (normalizedPayment.contains('authorized')) {
        return 'Payment is authorized and pending release after rejection.';
      }
      if (normalizedPayment.contains('paid')) {
        return 'Payment was captured. Refund is being processed after rejection.';
      }
      return null;
    }

    if (booking.status == BookingStatus.cancelled) {
      if (normalizedPayment.contains('refunded')) {
        return 'Payment refunded after cancellation.';
      }
      if (normalizedPayment.contains('cancelled')) {
        return 'Payment authorization released after cancellation.';
      }
      return null;
    }

    return null;
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
      case BookingStatus.rejected:
        return Colors.deepOrange;
      case BookingStatus.onTheWay:
        return Colors.teal;
      case BookingStatus.unknown:
        return const Color(0xFF666666);
    }
  }
}
