import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:passenger_app/core/widgets/top_alert.dart';
import 'package:passenger_app/features/auth/presentation/pages/phone_login_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  String _phoneNumber = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _loadUserData();
  }

  Widget _buildMainProfileMenu() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
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
                builder: (_) => const _BookingHistoryRoutePage(),
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


  Future<void> _loadUserData() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _phoneNumber = currentUser.phoneNumber ?? '';
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists && mounted) {
        setState(() {
          _nameController.text = userDoc.data()?['name'] ?? '';
          _emailController.text = userDoc.data()?['email'] ?? '';
        });
      } else if (mounted) {
        setState(() {
          _emailController.text = currentUser.email ?? '';
        });
      }
    }
  }


  Future<void> _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Logout"),
          content: const Text("Are you sure you want to logout?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text("Logout"),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && context.mounted) {
      await FirebaseAuth.instance.signOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PhoneLoginPage()),
        (route) => false,
      );
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
                        _nameController.text.isNotEmpty ? _nameController.text : 'Passenger',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phoneNumber,
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
                child: _buildMainProfileMenu(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}

class _AccountManagementRoutePage extends StatefulWidget {
  const _AccountManagementRoutePage();

  @override
  State<_AccountManagementRoutePage> createState() => _AccountManagementRoutePageState();
}

class _AccountManagementRoutePageState extends State<_AccountManagementRoutePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final TextEditingController _phoneController = TextEditingController();
  String _phoneNumber = '';
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    _phoneNumber = currentUser.phoneNumber ?? '';
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();

    if (!mounted) {
      return;
    }

    setState(() {
      _nameController.text = userDoc.data()?['name'] ?? '';
      _emailController.text = userDoc.data()?['email'] ?? currentUser.email ?? '';
      _phoneController.text = _phoneNumber;
    });
  }

  Future<void> _saveUserData() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'updatedAt': DateTime.now(),
      });

      if (_emailController.text.trim() != currentUser.email) {
        await currentUser.verifyBeforeUpdateEmail(_emailController.text.trim());
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isEditing = false;
      });

      showTopSuccess(context, message: 'Profile updated successfully');
    } catch (e) {
      if (!mounted) {
        return;
      }

      showTopError(context, message: 'Failed to update profile: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text('This action cannot be undone. All your data will be permanently deleted. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
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

    setState(() {
      _isSaving = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).delete();
      await currentUser.delete();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneLoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      showTopError(context, message: 'Error deleting account: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Full Name',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
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
                    if (_isEditing && (value == null || value.trim().isEmpty)) {
                      return 'Name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Email Address',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
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
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                        return 'Enter a valid email address';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Phone Number',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                          onPressed: _isSaving ? null : _saveUserData,
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _isEditing = false;
                                  });
                                  _loadUserData();
                                },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0066CC)),
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
                    onPressed: _isSaving ? null : _deleteAccount,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red, width: 1.5),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          )
                        : const Text(
                            'Delete Account',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red),
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

enum _BookingHistoryFilter {
  all,
  active,
  completed,
  cancelled,
}

class _BookingHistoryRoutePage extends StatefulWidget {
  const _BookingHistoryRoutePage();

  @override
  State<_BookingHistoryRoutePage> createState() => _BookingHistoryRoutePageState();
}

class _BookingHistoryRoutePageState extends State<_BookingHistoryRoutePage> {
  _BookingHistoryFilter _selectedFilter = _BookingHistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking History'),
        centerTitle: true,
      ),
      body: currentUser == null
          ? const Center(child: Text('Please sign in to view your bookings.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('userId', isEqualTo: currentUser.uid)
                .snapshots(includeMetadataChanges: true),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildHistoryState(
                    icon: Icons.receipt_long,
                    title: 'Unable to load bookings',
                    message: 'Please check your connection and try again.',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = [...(snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])]
                  ..sort((a, b) {
                    final aTimestamp = a.data()['createdAt'];
                    final bTimestamp = b.data()['createdAt'];
                    if (aTimestamp is Timestamp && bTimestamp is Timestamp) {
                      return bTimestamp.compareTo(aTimestamp);
                    }
                    if (bTimestamp is Timestamp) {
                      return 1;
                    }
                    if (aTimestamp is Timestamp) {
                      return -1;
                    }
                    return 0;
                  });

                if (docs.isEmpty) {
                  return _BookingHistoryRoutePageState._buildHistoryState(
                    icon: Icons.directions_boat,
                    title: 'No bookings yet',
                    message: 'Your completed and upcoming water taxi bookings will appear here.',
                  );
                }

                final filteredDocs = docs.where((doc) {
                  final status = (doc.data()['status'] ?? '').toString().toLowerCase();
                  switch (_selectedFilter) {
                    case _BookingHistoryFilter.active:
                      return _isActiveStatus(status);
                    case _BookingHistoryFilter.completed:
                      return status == 'completed';
                    case _BookingHistoryFilter.cancelled:
                      return status == 'cancelled';
                    case _BookingHistoryFilter.all:
                      return true;
                  }
                }).toList();

                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildFilterChips(),
                    const SizedBox(height: 16),
                    if (filteredDocs.isEmpty)
                      _buildHistoryState(
                        icon: Icons.filter_list,
                        title: 'No ${_filterLabel(_selectedFilter).toLowerCase()} bookings',
                        message: 'Try a different filter to see other bookings.',
                      )
                    else
                      ...filteredDocs.map((doc) => _buildBookingCard(doc.data())),
                  ],
                );
              },
            ),
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
                color: isSelected ? const Color(0xFF0066CC) : const Color(0xFFDDE5F0),
              ),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFF0066CC) : const Color(0xFF555555),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static bool _isActiveStatus(String status) {
    switch (status) {
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
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildBookingCard(Map<String, dynamic> booking) {
    final bookingId = (booking['bookingId'] ?? '').toString();
    final origin = (booking['origin'] ?? 'Unknown origin').toString();
    final destination = (booking['destination'] ?? 'Unknown destination').toString();
    final totalFare = _toDouble(booking['totalFare'] ?? booking['fare']);
    final passengerCount = _toInt(booking['passengerCount']);
    final paymentMethod = _formatPaymentMethod((booking['paymentMethod'] ?? 'unknown').toString());
    final status = (booking['status'] ?? 'pending').toString();
    final statusColor = _statusColor(status);
    final createdAt = _formatTimestamp(booking['createdAt']);

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
                  bookingId.isEmpty ? 'Booking' : bookingId,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatStatusLabel(status),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHistoryRow(Icons.location_on, 'Route', '$origin -> $destination'),
          const SizedBox(height: 8),
          _buildHistoryRow(Icons.people, 'Passengers', passengerCount == null ? 'Unavailable' : '$passengerCount'),
          const SizedBox(height: 8),
          _buildHistoryRow(Icons.account_balance_wallet, 'Payment', paymentMethod),
          const SizedBox(height: 8),
          _buildHistoryRow(Icons.schedule, 'Booked At', createdAt),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Fare',
                style: TextStyle(fontSize: 13, color: Color(0xFF666666), fontWeight: FontWeight.w600),
              ),
              Text(
                totalFare == null ? 'Unavailable' : 'RM ${totalFare.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 15, color: Color(0xFF0066CC), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
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
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF666666)),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
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

  static double? _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final local = value.toDate().toLocal();
      final month = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '${local.year}-$month-$day $hour:$minute';
    }
    return 'Unavailable';
  }

  static String _formatPaymentMethod(String paymentMethod) {
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
