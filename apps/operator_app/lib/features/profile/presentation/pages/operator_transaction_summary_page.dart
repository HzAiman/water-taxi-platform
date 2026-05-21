import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:operator_app/core/theme/operator_brand.dart';
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
  static const Color _brandOrange = OperatorBrand.orange;
  static const Color _brandMagenta = OperatorBrand.magenta;

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

  Future<void> _selectSummaryPeriod(SummaryPeriod period) async {
    final vm = context.read<OperatorTransactionSummaryViewModel>();
    if (period != SummaryPeriod.custom) {
      vm.selectPeriod(period);
      return;
    }

    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          vm.customPeriodStart != null && vm.customPeriodEnd != null
          ? DateTimeRange(
              start: DateTime(
                vm.customPeriodStart!.year,
                vm.customPeriodStart!.month,
                vm.customPeriodStart!.day,
              ),
              end: DateTime(
                vm.customPeriodEnd!.year,
                vm.customPeriodEnd!.month,
                vm.customPeriodEnd!.day,
              ),
            )
          : DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day),
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _brandMagenta,
              secondary: _brandOrange,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) {
      return;
    }
    vm.selectCustomPeriod(picked.start, picked.end);
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                        runSpacing: 8,
                        children: SummaryPeriod.values
                            .map(
                              (p) => ChoiceChip(
                                avatar: p == SummaryPeriod.custom
                                    ? const Icon(
                                        Icons.date_range_rounded,
                                        size: 18,
                                      )
                                    : null,
                                label: Text(p.label),
                                selected: vm.selectedPeriod == p,
                                selectedColor: _brandMagenta.withValues(
                                  alpha: 0.16,
                                ),
                                backgroundColor: const Color(0xFFF8FAFD),
                                checkmarkColor: _brandMagenta,
                                labelStyle: TextStyle(
                                  color: vm.selectedPeriod == p
                                      ? _brandMagenta
                                      : const Color(0xFF4B5B73),
                                  fontWeight: FontWeight.w800,
                                ),
                                side: BorderSide(
                                  color: vm.selectedPeriod == p
                                      ? _brandMagenta.withValues(alpha: 0.35)
                                      : const Color(0xFFDDE5F0),
                                ),
                                onSelected: (_) =>
                                    unawaited(_selectSummaryPeriod(p)),
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
                          color: _brandMagenta.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _brandMagenta.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              color: _brandMagenta,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                vm.selectedPeriodRangeLabel,
                                style: const TextStyle(
                                  color: Color(0xFF4B5B73),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
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
                              'Search by route, status, passenger, or phone',
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
