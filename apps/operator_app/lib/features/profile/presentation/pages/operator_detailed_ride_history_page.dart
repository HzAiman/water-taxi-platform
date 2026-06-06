import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:operator_app/core/theme/operator_brand.dart';
import 'package:operator_app/core/widgets/gradient_app_bar.dart';
import 'package:operator_app/features/profile/presentation/viewmodels/operator_transaction_summary_view_model.dart';
import 'package:operator_app/features/profile/presentation/widgets/operator_transaction_summary_widgets.dart';

class OperatorDetailedRideHistoryPage extends StatefulWidget {
  const OperatorDetailedRideHistoryPage({super.key});

  @override
  State<OperatorDetailedRideHistoryPage> createState() =>
      _OperatorDetailedRideHistoryPageState();
}

class _OperatorDetailedRideHistoryPageState
    extends State<OperatorDetailedRideHistoryPage> {
  static const Color _brandMagenta = OperatorBrand.magenta;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final initialQuery =
        context.read<OperatorTransactionSummaryViewModel>().historySearchQuery;
    _searchController = TextEditingController(text: initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final foreground = selected ? _brandMagenta : const Color(0xFF4B5B73);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _brandMagenta.withValues(alpha: 0.15),
      backgroundColor: const Color(0xFFF8FAFD),
      checkmarkColor: _brandMagenta,
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w800),
      side: BorderSide(
        color: selected
            ? _brandMagenta.withValues(alpha: 0.36)
            : const Color(0xFFDDE5F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (_) => onSelected(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OperatorTransactionSummaryViewModel>();

    return Scaffold(
      appBar: const GradientAppBar(title: 'Detailed Ride History'),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: HistoryFilter.values
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFilterChip(
                              label: f.label,
                              selected: vm.selectedHistoryFilter == f,
                              onSelected: () => vm.selectHistoryFilter(f),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: _brandMagenta),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              vm.setHistorySearchQuery('');
                              setState(() {});
                            },
                          )
                        : null,
                    hintText: 'Search by route, status, passenger, or phone',
                  ),
                  onChanged: (val) {
                    vm.setHistorySearchQuery(val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: vm.historyForSelectedPeriod.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No rides found for selected filters.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: vm.historyForSelectedPeriod.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final booking = vm.historyForSelectedPeriod[index];
                      return RideHistoryTile(booking: booking);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
