/// Single source of truth for displaying money in the app — BDT (Bangladeshi
/// Taka), matching the bKash payment flow everywhere else. Kept as a plain
/// function (not `intl`'s NumberFormat) to stay consistent with the rest of
/// the app's lightweight, no-locale-dependency formatting (see date_format.dart).
String formatCurrency(num amount) => '৳${amount.toStringAsFixed(2)}';
