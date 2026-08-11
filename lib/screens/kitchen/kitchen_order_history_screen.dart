import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/kitchen_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/date_format.dart';
import '../../widgets/detail_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_pill.dart';

/// The kitchen's full order history, reached by tapping "Orders" on the
/// dashboard — shows who ordered (name + phone), the items and quantities,
/// the bKash transaction ID, and when the order was placed vs.
/// delivered/completed. Watches KitchenProvider directly (rather than
/// taking a static order list) so it stays live if a new order lands while
/// this screen is open.
class KitchenOrderHistoryScreen extends StatelessWidget {
  const KitchenOrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final orders = context.watch<KitchenProvider>().orders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${orders.length} order${orders.length == 1 ? '' : 's'} total',
              style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: orders.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Orders placed with your kitchen will show up here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return _HistoryOrderCard(order: order);
              },
            ),
    );
  }
}

class _HistoryOrderCard extends StatelessWidget {
  final Order order;
  const _HistoryOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final completedOrDeliveredAt = order.completedAt ?? order.deliveredAt;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.customerName ?? 'Customer',
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatCurrency(order.totalAmount),
                  style: text.titleMedium?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(order.customerPhone!, style: text.bodySmall),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            StatusPill(status: order.status),

            if (order.items != null && order.items!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              ...order.items!.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text('${item.menuItemName} × ${item.quantity}', style: text.bodySmall)),
                      Text(formatCurrency(item.price * item.quantity), style: text.bodySmall),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            DetailRow(label: 'TrxID', value: order.customerBkashTxnId ?? '—'),
            DetailRow(label: 'Placed', value: formatDateTime(order.createdAt)),
            DetailRow(
              label: order.completedAt != null ? 'Completed' : 'Delivered',
              value: completedOrDeliveredAt != null ? formatDateTime(completedOrDeliveredAt) : 'Not yet',
            ),
          ],
        ),
      ),
    );
  }
}
