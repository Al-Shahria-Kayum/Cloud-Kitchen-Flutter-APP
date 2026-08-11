import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/rider_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/detail_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_pill.dart';

/// The rider's completed-delivery history, reached from the dashboard.
class RiderOrderHistoryScreen extends StatefulWidget {
  final String riderId;
  const RiderOrderHistoryScreen({super.key, required this.riderId});

  @override
  State<RiderOrderHistoryScreen> createState() => _RiderOrderHistoryScreenState();
}

class _RiderOrderHistoryScreenState extends State<RiderOrderHistoryScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    final orders = await riderProvider.loadDeliveryHistory(widget.riderId);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      // loadDeliveryHistory swallows errors and returns [] on failure — an
      // empty result with an error message set is a load failure, not
      // "no deliveries yet", and the two must read differently to the rider.
      _hasError = orders.isEmpty && riderProvider.errorMessage != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery History')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _hasError
                          ? EmptyState(
                              icon: Icons.error_outline_rounded,
                              title: 'Couldn\'t load your history',
                              message: 'Check your connection and pull down to try again.',
                              actionLabel: 'Retry',
                              onAction: _load,
                            )
                          : const EmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: 'No deliveries yet',
                              message: 'Deliveries you complete will show up here.',
                            ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('From ${order.kitchenName ?? "Kitchen"}', style: text.titleMedium),
                                  ),
                                  Text(
                                    '+${formatCurrency(order.riderFee)}',
                                    style: text.titleMedium?.copyWith(color: context.appColors.success),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(order.customerName ?? 'Customer', style: text.bodyMedium),
                                  if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.phone_outlined, size: 14, color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(order.customerPhone!, style: text.bodySmall),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.location_on_outlined, size: 15, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(order.deliveryAddress, style: text.bodySmall)),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Divider(height: 1),
                              const SizedBox(height: AppSpacing.sm),
                              DetailRow(
                                label: 'Picked up',
                                value: order.pickedUpAt != null ? formatDateTime(order.pickedUpAt!) : '—',
                              ),
                              DetailRow(
                                label: 'Delivered',
                                value: order.deliveredAt != null ? formatDateTime(order.deliveredAt!) : '—',
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const StatusPill(status: 'completed'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
