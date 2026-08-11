import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order.dart';
import '../utils/date_format.dart';

/// PDF-specific money formatting — deliberately "BDT 150.00" rather than the
/// ৳ glyph the rest of the app uses (see utils/currency_format.dart): the
/// `pdf` package's default base14 fonts don't include Bengali script
/// glyphs, so rendering ৳ here would either draw blank or throw. Avoiding a
/// bundled Unicode font keeps this service dependency-free.
String _pdfCurrency(num amount) => 'BDT ${amount.toStringAsFixed(2)}';

/// Generates and downloads a payment-receipt PDF for a completed order.
///
/// The receipt's content is deliberately role-specific (not user-editable —
/// see item 6's design note): a customer sees an itemized order total, a
/// kitchen owner sees the payout breakdown (commission/rider fee/net). Both
/// share the same order/items/trxID/timestamps from the order record itself,
/// so there's a single source of truth and nothing here can drift from the
/// actual transaction.
class ReceiptPdfService {
  ReceiptPdfService._();

  static Future<void> downloadReceipt({
    required Order order,
    required bool forKitchenOwner,
  }) async {
    // Menu item / person names in this app are frequently Bengali script
    // (e.g. real kitchen menu items like "ইলিশ মাছ"), which the pdf package's
    // default base14 (Helvetica-family) fonts cannot render — that mismatch
    // is what previously surfaced as "could not generate the receipt" any
    // time an order touched Bengali text. Noto Sans Bengali covers it.
    final baseFont = await PdfGoogleFonts.notoSansBengaliRegular();
    final boldFont = await PdfGoogleFonts.notoSansBengaliBold();
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont));
    final netPayout = order.totalAmount - order.commissionAmount - order.riderFee;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Cloud Kitchen', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                forKitchenOwner ? 'Payout Statement' : 'Payment Receipt',
                style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),
              _row('Order ID', '#${order.id.substring(0, 8).toUpperCase()}'),
              _row('Kitchen', order.kitchenName ?? '—'),
              if (!forKitchenOwner) _row('Customer', order.customerName ?? '—'),
              if (forKitchenOwner && order.riderName != null) _row('Rider', order.riderName!),
              _row('Placed', formatDateTime(order.createdAt)),
              if (order.completedAt != null) _row('Completed', formatDateTime(order.completedAt!)),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text('Items', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...(order.items ?? []).map(
                (item) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${item.menuItemName} × ${item.quantity}'),
                      pw.Text(_pdfCurrency(item.price * item.quantity)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (forKitchenOwner) ...[
                pw.Text('Payout Breakdown', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                _row('Gross order amount', _pdfCurrency(order.totalAmount)),
                _row('Platform commission', '-${_pdfCurrency(order.commissionAmount)}'),
                _row('Rider delivery fee', '-${_pdfCurrency(order.riderFee)}'),
                pw.SizedBox(height: 6),
                pw.Divider(),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Net payout', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_pdfCurrency(netPayout), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 12),
                _row('Rider paid', order.riderPaymentConfirmed ? 'Yes' : 'Not yet'),
              ] else ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Paid', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_pdfCurrency(order.totalAmount), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Text('Payment', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              _row('Method', 'bKash'),
              _row('Transaction ID', order.customerBkashTxnId ?? '—'),
              if (order.paymentConfirmedAt != null) _row('Confirmed on', formatDateTime(order.paymentConfirmedAt!)),
              pw.SizedBox(height: 24),
              pw.Text(
                'This receipt was generated automatically from the order record and cannot be edited.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'receipt_${order.id.substring(0, 8)}.pdf',
    );
  }

  static pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
