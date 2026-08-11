import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Centralizes the order-status → label/color/icon mapping that used to be
/// duplicated (and drifting out of sync) across the customer, kitchen and
/// rider screens. One place to look when a new status is added.
class OrderStatusMeta {
  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;
  const OrderStatusMeta({required this.label, required this.fg, required this.bg, required this.icon});

  static OrderStatusMeta of(BuildContext context, String status) {
    final c = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'pending':
        return OrderStatusMeta(label: 'Order placed', fg: c.warning, bg: c.warningContainer, icon: Icons.schedule_rounded);
      case 'accepted':
        return OrderStatusMeta(label: 'Accepted', fg: scheme.primary, bg: scheme.primaryContainer, icon: Icons.check_circle_outline_rounded);
      case 'preparing':
        return OrderStatusMeta(label: 'Preparing', fg: scheme.primary, bg: scheme.primaryContainer, icon: Icons.soup_kitchen_rounded);
      case 'ready':
        return OrderStatusMeta(label: 'Ready for pickup', fg: c.success, bg: c.successContainer, icon: Icons.inventory_2_rounded);
      case 'awaiting_rider':
        return OrderStatusMeta(label: 'Finding a rider', fg: c.success, bg: c.successContainer, icon: Icons.search_rounded);
      case 'rider_assigned':
        return OrderStatusMeta(label: 'Rider assigned', fg: scheme.secondary, bg: scheme.secondary.withValues(alpha: 0.12), icon: Icons.two_wheeler_rounded);
      case 'picked_up':
        return OrderStatusMeta(label: 'Picked up', fg: scheme.secondary, bg: scheme.secondary.withValues(alpha: 0.12), icon: Icons.shopping_bag_rounded);
      case 'on_the_way':
        return OrderStatusMeta(label: 'On the way', fg: scheme.secondary, bg: scheme.secondary.withValues(alpha: 0.12), icon: Icons.moped_rounded);
      case 'arrived':
        return OrderStatusMeta(label: 'Rider arrived', fg: scheme.secondary, bg: scheme.secondary.withValues(alpha: 0.12), icon: Icons.pin_drop_rounded);
      case 'delivered':
        return OrderStatusMeta(label: 'Awaiting your confirmation', fg: c.warning, bg: c.warningContainer, icon: Icons.mark_email_unread_rounded);
      case 'completed':
        return OrderStatusMeta(label: 'Completed', fg: c.success, bg: c.successContainer, icon: Icons.task_alt_rounded);
      case 'rejected':
        return OrderStatusMeta(label: 'Rejected', fg: scheme.error, bg: scheme.error.withValues(alpha: 0.1), icon: Icons.cancel_rounded);
      default:
        return OrderStatusMeta(label: status, fg: scheme.onSurface, bg: scheme.outline.withValues(alpha: 0.15), icon: Icons.help_outline_rounded);
    }
  }
}

/// A compact status pill: icon + label, tinted per status.
class StatusPill extends StatelessWidget {
  final String status;
  final bool dense;
  const StatusPill({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final meta = OrderStatusMeta.of(context, status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 11, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(color: meta.bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: dense ? 12 : 14, color: meta.fg),
          SizedBox(width: dense ? 4 : 6),
          Text(
            meta.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: meta.fg, fontSize: dense ? 10.5 : 11.5),
          ),
        ],
      ),
    );
  }
}
