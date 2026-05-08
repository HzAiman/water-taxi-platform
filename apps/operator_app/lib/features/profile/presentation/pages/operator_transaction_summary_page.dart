import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:operator_app/core/widgets/gradient_app_bar.dart';
import 'package:operator_app/core/widgets/top_alert.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_transaction_summary_widgets.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

class OperatorTransactionSummaryPage extends StatefulWidget {
  const OperatorTransactionSummaryPage({super.key});

  @override
  State<OperatorTransactionSummaryPage> createState() =>
      _OperatorTransactionSummaryPageState();
}

class _OperatorTransactionSummaryPageState
    extends State<OperatorTransactionSummaryPage> {
  static const Color _brandOrange = Color(0xFFFF7A00);
  static const Color _brandMagenta = Color(0xFFCA4B8C);

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

    _showOperationResult(result);
  }

  Future<void> _shareStatement(StatementRecord record) async {
    final result = await context
        .read<OperatorTransactionSummaryViewModel>()
        .shareStatement(record);

    _showOperationResult(result);
  }

  Future<void> _deleteStatement(StatementRecord record) async {
    final result = await context
        .read<OperatorTransactionSummaryViewModel>()
        .deleteStatement(record);

    _showOperationResult(result);
  }

  void _showOperationResult(OperationResult result) {
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
      appBar: const GradientAppBar(title: 'Ride / Transaction Summary'),
      body: vm.isLoading
          ? const Center(child: CircularProgressIndicator())
          : vm.error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(vm.error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                OperatorSummarySectionCard(
                  title: 'Completed Rides',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OperatorSummaryMetricChip(
                        label: 'Today',
                        value: vm.completedToday.toString(),
                      ),
                      OperatorSummaryMetricChip(
                        label: 'This Week',
                        value: vm.completedThisWeek.toString(),
                      ),
                      OperatorSummaryMetricChip(
                        label: 'This Month',
                        value: vm.completedThisMonth.toString(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OperatorSummarySectionCard(
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
                                selectedColor: _brandMagenta.withValues(
                                  alpha: 0.16,
                                ),
                                checkmarkColor: _brandMagenta,
                                onSelected: (_) => vm.selectPeriod(p),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _brandMagenta.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _brandMagenta.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Text(
                          vm.selectedPeriodRangeLabel,
                          style: const TextStyle(
                            color: Color(0xFF4B5B73),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OperatorSummaryInfoRow(
                        label: 'Total Earnings',
                        value:
                            'RM ${vm.selectedPeriodEarnings.toStringAsFixed(2)}',
                      ),
                      OperatorSummaryInfoRow(
                        label: 'Pending or Active Rides',
                        value: vm.selectedPeriodPendingOrActive.toString(),
                      ),
                      OperatorSummaryInfoRow(
                        label: 'Cancelled Rides',
                        value: vm.selectedPeriodCancelled.toString(),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: vm.isExporting
                              ? null
                              : const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [_brandOrange, _brandMagenta],
                                ),
                          color: vm.isExporting ? Colors.grey.shade300 : null,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: vm.isExporting
                              ? null
                              : [
                                  BoxShadow(
                                    color: _brandMagenta.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: vm.isExporting ? null : _export,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              surfaceTintColor: Colors.transparent,
                              foregroundColor: Colors.white,
                            ),
                            icon: vm.isExporting
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
                                : const Icon(Icons.picture_as_pdf),
                            label: Text(
                              vm.isExporting
                                  ? 'Generating Statement...'
                                  : 'Export ${vm.selectedPeriod.label} Statement (PDF)',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OperatorSummarySectionCard(
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
                                selectedColor: _brandOrange.withValues(
                                  alpha: 0.14,
                                ),
                                checkmarkColor: _brandMagenta,
                                onSelected: (_) => vm.selectHistoryFilter(f),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search, color: _brandMagenta),
                          hintText:
                              'Search by booking ID, route, status, or passenger',
                        ),
                        onChanged: vm.setHistorySearchQuery,
                      ),
                      const SizedBox(height: 12),
                      if (vm.historyForSelectedPeriod.isEmpty)
                        const Text('No rides found for selected filters.')
                      else
                        Column(
                          children: vm.historyForSelectedPeriod
                              .map((b) => RideHistoryTile(booking: b))
                              .toList(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OperatorSummarySectionCard(
                  title: 'Income Documents / Statements',
                  child: vm.statements.isEmpty
                      ? const Text('No saved statements yet.')
                      : Column(
                          children: vm.statements
                              .map(
                                (s) => StatementTile(
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
