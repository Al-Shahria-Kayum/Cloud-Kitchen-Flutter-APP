/// Shared short date/time formatting for order-history and receipt views —
/// "5/8/2026 14:32" in the viewer's local time. No `intl` DateFormat needed
/// for this simple, locale-agnostic shape.
String formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Date-only variant, e.g. "5/8/2026".
String formatDate(DateTime dt) {
  final local = dt.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}
