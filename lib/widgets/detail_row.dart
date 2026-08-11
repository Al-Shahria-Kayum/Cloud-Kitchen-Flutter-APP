import 'package:flutter/material.dart';

/// A "label ⋯ value" line for history/receipt detail lists — a consistent
/// look for TrxID, placed/delivered timestamps, and similar metadata rows.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const DetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
