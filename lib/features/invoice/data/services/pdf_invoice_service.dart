import 'dart:typed_data';

import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef PdfLayoutCallback = Future<bool> Function({
  required Future<Uint8List> Function(PdfPageFormat format) onLayout,
  required String name,
});

/// Generates Vietnamese POS invoices in PDF format and opens the Android/system print dialog.
class PdfInvoiceService {
  PdfInvoiceService({
    Future<pw.Font> Function()? loadRegularFont,
    Future<pw.Font> Function()? loadBoldFont,
    PdfLayoutCallback? layoutPdfCallback,
  })  : _loadRegularFont = loadRegularFont ?? PdfGoogleFonts.notoSansRegular,
        _loadBoldFont = loadBoldFont ?? PdfGoogleFonts.notoSansBold,
        _layoutPdfCallback = layoutPdfCallback ?? _defaultLayoutPdf;

  static const PdfPageFormat defaultPageFormat = PdfPageFormat.a4;
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  final Future<pw.Font> Function() _loadRegularFont;
  final Future<pw.Font> Function() _loadBoldFont;
  final PdfLayoutCallback _layoutPdfCallback;

  static Future<bool> _defaultLayoutPdf({
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
    required String name,
  }) {
    return Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: defaultPageFormat,
    );
  }

  /// Opens the platform print dialog for [invoice].
  Future<void> printInvoice(Invoice invoice) async {
    final regularFont = await _loadRegularFont();
    final boldFont = await _loadBoldFont();

    await _layoutPdfCallback(
      name: 'HoaDon_${invoice.orderCode}',
      onLayout: (format) => buildInvoicePdf(
        invoice,
        format: format,
        regularFont: regularFont,
        boldFont: boldFont,
      ),
    );
  }

  /// Builds raw PDF bytes containing all required store, order, line-item, and payment fields.
  Future<Uint8List> buildInvoicePdf(
    Invoice invoice, {
    PdfPageFormat format = defaultPageFormat,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) async {
    final regular = regularFont ?? await _loadRegularFont();
    final bold = boldFont ?? await _loadBoldFont();
    final localCreatedAt = invoice.createdAt.toLocal();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(invoice),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 8),
          _buildOrderMetadata(invoice, localCreatedAt),
          pw.SizedBox(height: 12),
          _buildItemsTable(invoice),
          pw.SizedBox(height: 14),
          _buildTotalsSection(invoice),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              'Cảm ơn quý khách và hẹn gặp lại!',
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(Invoice invoice) {
    final store = invoice.store;
    final trimmedName = store.name.trim();
    final monogram = trimmedName.isNotEmpty
        ? String.fromCharCode(trimmedName.runes.first).toUpperCase()
        : 'P';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 48,
          height: 48,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.5, color: PdfColors.grey700),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            color: PdfColors.grey200,
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                monogram,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
              ),
              if (store.logoUrl != null && store.logoUrl!.isNotEmpty)
                pw.Text('LOGO', style: const pw.TextStyle(fontSize: 6)),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                store.name,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
              ),
              if (store.phone.isNotEmpty)
                pw.Text('SĐT: ${store.phone}', style: const pw.TextStyle(fontSize: 10)),
              if (store.address.isNotEmpty)
                pw.Text(
                  'Địa chỉ: ${store.address}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
            ],
          ),
        ),
        pw.Text(
          'HÓA ĐƠN BÁN HÀNG',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  pw.Widget _buildOrderMetadata(Invoice invoice, DateTime localCreatedAt) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Mã đơn: ${invoice.orderCode}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text(
              'Nhân viên: ${invoice.staffName}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Ngày hóa đơn: ${_dateFormat.format(localCreatedAt)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Thời gian tạo: ${_timeFormat.format(localCreatedAt)}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable(Invoice invoice) {
    const headers = [
      'Mã',
      'Tên sản phẩm',
      'ĐVT',
      'SL',
      'Giá bán',
      '% CK',
      'Tiền CK',
      'VAT',
      'Thành tiền',
      'Ghi chú',
    ];

    final rows = invoice.items.map((item) {
      return [
        item.sku,
        item.name,
        item.unit,
        _formatNumber(item.quantity),
        CurrencyFormatter.formatVnd(item.unitPrice),
        '${_formatNumber(item.discountPercent)}%',
        CurrencyFormatter.formatVnd(item.discountAmount),
        '${_formatNumber(item.vatRate)}%\n(${CurrencyFormatter.formatVnd(item.vatAmount)})',
        CurrencyFormatter.formatVnd(item.lineTotal),
        item.note.isEmpty ? '-' : item.note,
      ];
    }).toList(growable: false);

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
        9: pw.Alignment.centerLeft,
      },
    );
  }

  pw.Widget _buildTotalsSection(Invoice invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            _summaryRow(
              'Tổng giá trị đơn:',
              CurrencyFormatter.formatVnd(invoice.subtotal),
            ),
            _summaryRow(
              '% giảm giá:',
              '${_formatNumber(invoice.discountPercent)}%',
            ),
            _summaryRow(
              'Tiền giảm:',
              CurrencyFormatter.formatVnd(invoice.discountAmount),
            ),
            pw.Divider(thickness: 0.8),
            _summaryRow(
              'Tổng cần thanh toán:',
              CurrencyFormatter.formatVnd(invoice.totalPayable),
              bold: true,
            ),
            pw.SizedBox(height: 4),
            _summaryRow('Hình thức thanh toán:', invoice.paymentMethod),
          ],
        ),
      ),
    );
  }

  pw.Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontSize: bold ? 11 : 9.5,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
}
