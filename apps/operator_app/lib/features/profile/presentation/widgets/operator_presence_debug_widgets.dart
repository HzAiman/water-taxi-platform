import 'package:flutter/material.dart';

import 'package:operator_app/features/profile/presentation/debug/operator_presence_debug_utils.dart';

class OperatorPresenceSectionCard extends StatelessWidget {
  const OperatorPresenceSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

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

class OperatorPresenceMetricChip extends StatelessWidget {
  const OperatorPresenceMetricChip({
    super.key,
    required this.label,
    required this.value,
  });

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
            style: const TextStyle(fontSize: 12, color: Color(0xFF4B5B73)),
          ),
        ],
      ),
    );
  }
}

class OperatorPresenceListTile extends StatelessWidget {
  const OperatorPresenceListTile({
    super.key,
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
    final statusColor = isOnline
        ? const Color(0xFF1D6E3A)
        : const Color(0xFF8A1C1C);
    final statusBg = isOnline
        ? const Color(0xFFEAF7EE)
        : const Color(0xFFFFEAEA);

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
                  'Updated: ${OperatorPresenceDebugUtils.formatTimestamp(updatedAt)}',
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

class OperatorPresenceKeyValueRow extends StatelessWidget {
  const OperatorPresenceKeyValueRow({
    super.key,
    required this.label,
    required this.value,
  });

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

class OperatorPresenceErrorState extends StatelessWidget {
  const OperatorPresenceErrorState({super.key, required this.message});

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
