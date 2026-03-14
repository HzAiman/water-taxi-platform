import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorPresenceDebugPage extends StatefulWidget {
  const OperatorPresenceDebugPage({
    super.key,
    this.firestore,
    this.currentOperatorId,
  });

  final FirebaseFirestore? firestore;
  final String? currentOperatorId;

  @override
  State<OperatorPresenceDebugPage> createState() =>
      _OperatorPresenceDebugPageState();
}

class _OperatorPresenceDebugPageState extends State<OperatorPresenceDebugPage> {
  bool _isSyncing = false;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _syncPresence({
    required String operatorId,
    required bool profileOnline,
  }) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await _db.collection(FirestoreCollections.operatorPresence).doc(operatorId).set({
        OperatorPresenceFields.isOnline: profileOnline,
        OperatorPresenceFields.updatedAt: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Presence synced to ${profileOnline ? 'online' : 'offline'} from operator profile.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Presence sync failed: $e'),
          backgroundColor: const Color(0xFF8A1C1C),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final operatorId =
        widget.currentOperatorId ?? FirebaseAuth.instance.currentUser?.uid;

    if (operatorId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Debug')),
        body: const Center(child: Text('No signed-in operator available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presence Debug'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection(FirestoreCollections.operatorPresence).snapshots(),
        builder: (context, presenceSnapshot) {
          if (presenceSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (presenceSnapshot.hasError) {
            return _ErrorState(
              message: 'Failed to load operator presence: ${presenceSnapshot.error}',
            );
          }

          final docs = presenceSnapshot.data?.docs.toList() ?? [];
          docs.sort((a, b) => _compareTimestamps(
                b.data()[OperatorPresenceFields.updatedAt],
                a.data()[OperatorPresenceFields.updatedAt],
              ));

          final onlineCount = docs
              .where((doc) => doc.data()[OperatorPresenceFields.isOnline] == true)
              .length;
          final staleCount = docs
              .where((doc) {
                final updatedAt = _asDateTime(
                  doc.data()[OperatorPresenceFields.updatedAt],
                );
                if (updatedAt == null) return true;
                return DateTime.now().difference(updatedAt) >
                    const Duration(minutes: 10);
              })
              .length;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection(FirestoreCollections.operators)
                .doc(operatorId)
                .snapshots(),
            builder: (context, operatorSnapshot) {
              final operatorData = operatorSnapshot.data?.data();
              final operatorOnline = operatorData?[OperatorFields.isOnline] == true;
              final currentPresence = docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>?>().firstWhere(
                    (doc) => doc?.id == operatorId,
                    orElse: () => null,
                  );
              final presenceData = currentPresence?.data();
              final presenceOnline =
                  presenceData?[OperatorPresenceFields.isOnline] == true;
              final mismatch = operatorData != null &&
                  presenceData != null &&
                  operatorOnline != presenceOnline;
                final profileOnline = operatorOnline;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    title: 'Current Operator',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KeyValueRow(label: 'UID', value: operatorId),
                        _KeyValueRow(
                          label: 'Profile isOnline',
                          value: operatorData == null
                              ? 'Missing operator profile'
                              : operatorOnline.toString(),
                        ),
                        _KeyValueRow(
                          label: 'Presence isOnline',
                          value: presenceData == null
                              ? 'Missing presence doc'
                              : presenceOnline.toString(),
                        ),
                        _KeyValueRow(
                          label: 'Presence updated',
                          value: _formatTimestamp(
                            _asDateTime(
                              presenceData?[OperatorPresenceFields.updatedAt],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mismatch
                                ? const Color(0xFFFFF4E5)
                                : const Color(0xFFEAF7EE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            mismatch
                                ? 'Presence mismatch detected: profile and operator_presence disagree.'
                                : 'Presence sync looks consistent for this operator.',
                            style: TextStyle(
                              color: mismatch
                                  ? const Color(0xFF8A5200)
                                  : const Color(0xFF1D6E3A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (operatorData == null || _isSyncing)
                                ? null
                                : () => _syncPresence(
                                      operatorId: operatorId,
                                      profileOnline: profileOnline,
                                    ),
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.sync),
                            label: Text(
                              _isSyncing
                                  ? 'Syncing Presence...'
                                  : 'Sync My Presence Now',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Presence Summary',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetricChip(label: 'Total docs', value: docs.length.toString()),
                        _MetricChip(
                          label: 'Online operators',
                          value: onlineCount.toString(),
                        ),
                        _MetricChip(label: 'Stale docs', value: staleCount.toString()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Presence Documents',
                    child: docs.isEmpty
                        ? const Text('No operator_presence documents found.')
                        : Column(
                            children: [
                              for (final doc in docs)
                                _PresenceListTile(
                                  operatorId: doc.id,
                                  isOnline: doc.data()[OperatorPresenceFields.isOnline] == true,
                                  updatedAt: _asDateTime(
                                    doc.data()[OperatorPresenceFields.updatedAt],
                                  ),
                                  isStale: (() {
                                    final updatedAt = _asDateTime(
                                      doc.data()[OperatorPresenceFields.updatedAt],
                                    );
                                    if (updatedAt == null) return true;
                                    return DateTime.now().difference(updatedAt) >
                                        const Duration(minutes: 10);
                                  })(),
                                  isCurrentOperator: doc.id == operatorId,
                                ),
                            ],
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static int _compareTimestamps(dynamic left, dynamic right) {
    final leftDate = _asDateTime(left);
    final rightDate = _asDateTime(right);
    if (leftDate == null && rightDate == null) return 0;
    if (leftDate == null) return -1;
    if (rightDate == null) return 1;
    return leftDate.compareTo(rightDate);
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _formatTimestamp(DateTime? value) {
    if (value == null) return 'N/A';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute:$second';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0066CC),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4B5B73),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresenceListTile extends StatelessWidget {
  const _PresenceListTile({
    required this.operatorId,
    required this.isOnline,
    required this.updatedAt,
    required this.isStale,
    required this.isCurrentOperator,
  });

  final String operatorId;
  final bool isOnline;
  final DateTime? updatedAt;
  final bool isStale;
  final bool isCurrentOperator;

  @override
  Widget build(BuildContext context) {
    final statusColor = isOnline ? const Color(0xFF1D6E3A) : const Color(0xFF8A1C1C);
    final statusBg = isOnline ? const Color(0xFFEAF7EE) : const Color(0xFFFFEAEA);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrentOperator ? '$operatorId (current)' : operatorId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Updated: ${_OperatorPresenceDebugPageState._formatTimestamp(updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF66758A),
                  ),
                ),
                if (isStale) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'STALE (>10 min)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A5200),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isOnline ? 'ONLINE' : 'OFFLINE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B5B73),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF1A1A1A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF8A1C1C)),
        ),
      ),
    );
  }
}