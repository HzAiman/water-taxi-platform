import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorTransactionSummaryPage extends StatefulWidget {
  const OperatorTransactionSummaryPage({super.key});

  @override
  State<OperatorTransactionSummaryPage> createState() =>
      _OperatorTransactionSummaryPageState();
}

class _OperatorTransactionSummaryPageState
    extends State<OperatorTransactionSummaryPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (!mounted) return;
      context.read<OperatorTransactionSummaryViewModel>().initialize();
    });
  }

  Future<void> _export() async {
    final result = await context
        .read<OperatorTransactionSummaryViewModel>()
        .exportSelectedPeriodPdf();

    if (!mounted) return;
    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  Future<void> _shareStatement(StatementRecord record) async {
    final result =
        await context.read<OperatorTransactionSummaryViewModel>().shareStatement(record);

    if (!mounted) return;
    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
      case OperationFailure(:final title, :final message, :final isInfo):
        if (isInfo) {
          showTopInfo(context, title: title, message: message);
        } else {
          showTopError(context, title: title, message: message);
        }
    }
  }

  Future<void> _deleteStatement(StatementRecord record) async {
    final result = await context
        .read<OperatorTransactionSummaryViewModel>()
        .deleteStatement(record);

    if (!mounted) return;
    switch (result) {
      case OperationSuccess(:final message):
        showTopSuccess(context, message: message);
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
    final vm = context.watch<OperatorTransactionSummaryViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride / Transaction Summary'),
        centerTitle: true,
      ),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(vm.error!, textAlign: TextAlign.center),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionCard(
                      title: 'Completed Rides',
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _MetricChip(label: 'Today', value: vm.completedToday.toString()),
                          _MetricChip(label: 'This Week', value: vm.completedThisWeek.toString()),
                          _MetricChip(label: 'This Month', value: vm.completedThisMonth.toString()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Summary by Period',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: SummaryPeriod.values
                                .map(
                                  (p) => ChoiceChip(
                                    label: Text(p.label),
                                    selected: vm.selectedPeriod == p,
                                    onSelected: (_) => vm.selectPeriod(p),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            label: 'Total Earnings',
                            value:
                                'RM ${vm.selectedPeriodEarnings.toStringAsFixed(2)}',
                          ),
                          _InfoRow(
                            label: 'Pending or Active Rides',
                            value: vm.selectedPeriodPendingOrActive.toString(),
                          ),
                          _InfoRow(
                            label: 'Cancelled Rides',
                            value: vm.selectedPeriodCancelled.toString(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: vm.isExporting ? null : _export,
                              icon: vm.isExporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.picture_as_pdf),
                              label: Text(vm.isExporting
                                  ? 'Generating Statement...'
                                  : 'Export ${vm.selectedPeriod.label} Statement (PDF)'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Detailed Ride History',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: HistoryFilter.values
                                .map(
                                  (f) => ChoiceChip(
                                    label: Text(f.label),
                                    selected: vm.selectedHistoryFilter == f,
                                    onSelected: (_) => vm.selectHistoryFilter(f),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search by booking ID, route, status, or passenger',
                            ),
                            onChanged: vm.setHistorySearchQuery,
                          ),
                          const SizedBox(height: 12),
                          if (vm.historyForSelectedPeriod.isEmpty)
                            const Text('No rides found for selected filters.')
                          else
                            Column(
                              children: vm.historyForSelectedPeriod
                                  .map((b) => _RideHistoryTile(booking: b))
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Income Documents / Statements',
                      child: vm.statements.isEmpty
                          ? const Text('No saved statements yet.')
                          : Column(
                              children: vm.statements
                                  .map(
                                    (s) => _StatementTile(
                                      record: s,
                                      onShare: () => _shareStatement(s),
                                      onDelete: () => _deleteStatement(s),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                ),
    );
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F0)),
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
        borderRadius: BorderRadius.circular(12),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5B73),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RideHistoryTile extends StatelessWidget {
  const _RideHistoryTile({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    final fare = booking.totalFare > 0 ? booking.totalFare : booking.fare;
    final updated = booking.updatedAt ?? booking.createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.bookingId,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  booking.status.firestoreValue,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0066CC),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${booking.origin} -> ${booking.destination}'),
          const SizedBox(height: 4),
          Text('Fare: RM ${fare.toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          Text('Updated: ${_fmt(updated)}'),
        ],
      ),
    );
  }

  static String _fmt(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({
    required this.record,
    required this.onShare,
    required this.onDelete,
  });

  final StatementRecord record;
  final Future<void> Function() onShare;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final generated = _fmt(record.generatedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.fileName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Period: ${record.period.label}'),
          Text('Generated: $generated'),
          Text('Completed rides: ${record.completedRides}'),
          Text('Earnings: RM ${record.totalEarnings.toStringAsFixed(2)}'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onShare()),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(onDelete()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
