import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:operator_app/features/profile/presentation/debug/operator_presence_debug_utils.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_presence_debug_widgets.dart';
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
      await OperatorPresenceDebugUtils.syncPresence(
        db: _db,
        operatorId: operatorId,
        profileOnline: profileOnline,
      );

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
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Debug')),
        body: const Center(
          child: Text('Presence Debug is available in debug builds only.'),
        ),
      );
    }

    final operatorId =
        widget.currentOperatorId ?? FirebaseAuth.instance.currentUser?.uid;

    if (operatorId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Debug')),
        body: const Center(child: Text('No signed-in operator available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Presence Debug'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection(FirestoreCollections.operatorPresence)
            .snapshots(),
        builder: (context, presenceSnapshot) {
          if (presenceSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (presenceSnapshot.hasError) {
            return OperatorPresenceErrorState(
              message:
                  'Failed to load operator presence: ${presenceSnapshot.error}',
            );
          }

          final docs = presenceSnapshot.data?.docs.toList() ?? [];
          docs.sort(
            (a, b) => OperatorPresenceDebugUtils.compareTimestamps(
              b.data()[OperatorPresenceFields.updatedAt],
              a.data()[OperatorPresenceFields.updatedAt],
            ),
          );

          final onlineCount = docs
              .where(
                (doc) => doc.data()[OperatorPresenceFields.isOnline] == true,
              )
              .length;
          final staleCount = docs.where((doc) {
            final updatedAt = OperatorPresenceDebugUtils.asDateTime(
              doc.data()[OperatorPresenceFields.updatedAt],
            );
            return OperatorPresenceDebugUtils.isStale(updatedAt);
          }).length;
          final staleOnlineDocs = docs.where((doc) {
            if (doc.data()[OperatorPresenceFields.isOnline] != true) {
              return false;
            }
            final updatedAt = OperatorPresenceDebugUtils.asDateTime(
              doc.data()[OperatorPresenceFields.updatedAt],
            );
            return OperatorPresenceDebugUtils.isStale(updatedAt);
          }).toList();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _db
                .collection(FirestoreCollections.operators)
                .doc(operatorId)
                .snapshots(),
            builder: (context, operatorSnapshot) {
              final operatorData = operatorSnapshot.data?.data();
              final operatorOnline =
                  operatorData?[OperatorFields.isOnline] == true;
              final currentPresence = docs
                  .cast<QueryDocumentSnapshot<Map<String, dynamic>>?>()
                  .firstWhere(
                    (doc) => doc?.id == operatorId,
                    orElse: () => null,
                  );
              final presenceData = currentPresence?.data();
              final presenceOnline =
                  presenceData?[OperatorPresenceFields.isOnline] == true;
              final mismatch =
                  operatorData?.containsKey(OperatorFields.isOnline) == true &&
                  presenceData != null &&
                  operatorOnline != presenceOnline;
              final profileOnline =
                  operatorData?.containsKey(OperatorFields.isOnline) == true
                  ? operatorOnline
                  : presenceOnline;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  OperatorPresenceSectionCard(
                    title: 'Current Operator',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OperatorPresenceKeyValueRow(
                          label: 'UID',
                          value: operatorId,
                        ),
                        OperatorPresenceKeyValueRow(
                          label: 'Profile isOnline',
                          value: operatorData == null
                              ? 'Missing operator profile'
                              : operatorOnline.toString(),
                        ),
                        OperatorPresenceKeyValueRow(
                          label: 'Presence isOnline',
                          value: presenceData == null
                              ? 'Missing presence doc'
                              : presenceOnline.toString(),
                        ),
                        OperatorPresenceKeyValueRow(
                          label: 'Presence updated',
                          value: OperatorPresenceDebugUtils.formatTimestamp(
                            OperatorPresenceDebugUtils.asDateTime(
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
                  OperatorPresenceSectionCard(
                    title: 'Presence Summary',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OperatorPresenceMetricChip(
                          label: 'Total docs',
                          value: docs.length.toString(),
                        ),
                        OperatorPresenceMetricChip(
                          label: 'Online operators',
                          value: onlineCount.toString(),
                        ),
                        OperatorPresenceMetricChip(
                          label: 'Stale docs',
                          value: staleCount.toString(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Mark Stale Offline (Server Admin)'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Disabled in client app. Use the server-admin operation path for cleanup.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF66758A)),
                  ),
                  const SizedBox(height: 10),
                  OperatorPresenceSectionCard(
                    title: 'Dry Run Preview',
                    child: staleOnlineDocs.isEmpty
                        ? const Text(
                            'No stale online operators to mark offline.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Will mark offline (${staleOnlineDocs.length}):',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final doc in staleOnlineDocs)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF4E5),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        doc.id,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF8A5200),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  OperatorPresenceSectionCard(
                    title: 'Presence Documents',
                    child: docs.isEmpty
                        ? const Text('No operator_presence documents found.')
                        : Column(
                            children: [
                              for (final doc in docs)
                                OperatorPresenceListTile(
                                  operatorId: doc.id,
                                  isOnline:
                                      doc.data()[OperatorPresenceFields
                                          .isOnline] ==
                                      true,
                                  updatedAt:
                                      OperatorPresenceDebugUtils.asDateTime(
                                        doc.data()[OperatorPresenceFields
                                            .updatedAt],
                                      ),
                                  isStale: (() {
                                    final updatedAt =
                                        OperatorPresenceDebugUtils.asDateTime(
                                          doc.data()[OperatorPresenceFields
                                              .updatedAt],
                                        );
                                    return OperatorPresenceDebugUtils.isStale(
                                      updatedAt,
                                    );
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
}
