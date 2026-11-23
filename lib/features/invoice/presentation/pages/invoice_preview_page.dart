import 'dart:typed_data';

import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/invoice/data/services/escpos_raster_printer_service.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_cubit.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_state.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

typedef CaptureReceiptPngCallback = Future<Uint8List> Function(
  GlobalKey boundaryKey,
  int targetWidthPx,
);

/// Screen displaying the thermal receipt preview (`RepaintBoundary`) with ESC/POS and PDF printing.
class InvoicePreviewPage extends StatefulWidget {
  const InvoicePreviewPage({
    super.key,
    this.printerConfig = const PrinterConfig(),
    this.onOpenPrinterSettings,
    this.captureReceiptPng,
  });

  final PrinterConfig printerConfig;
  final VoidCallback? onOpenPrinterSettings;
  final CaptureReceiptPngCallback? captureReceiptPng;

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  final GlobalKey _receiptBoundaryKey = GlobalKey();

  PrinterConfig get _effectiveEscPosConfig {
    if (widget.printerConfig.mode == PrinterMode.pdfSystem) {
      return widget.printerConfig.copyWith(mode: PrinterMode.escPosLan);
    }
    return widget.printerConfig;
  }

  Future<void> _handleEscPosPrint(InvoiceCubit cubit) async {
    final config = _effectiveEscPosConfig;
    final targetWidthPx =
        EscPosRasterPrinterService.targetWidthForPaperMm(config.paperWidthMm);

    await cubit.printCurrentInvoice(
      config,
      capturePng: () {
        final customCapture = widget.captureReceiptPng;
        if (customCapture != null) {
          return customCapture(_receiptBoundaryKey, targetWidthPx);
        }
        return EscPosRasterPrinterService.captureReceiptBitmap(
          _receiptBoundaryKey,
          targetWidthPx: targetWidthPx,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InvoiceCubit, InvoiceState>(
      listenWhen: (previous, current) =>
          previous.errorNonce != current.errorNonce ||
          previous.printSuccessNonce != current.printSuccessNonce,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
        } else if (state.printSuccessNonce > 0) {
          final modeLabel = state.lastPrintedMode == PrinterMode.pdfSystem
              ? 'PDF / Android Print'
              : 'máy in nhiệt ESC/POS';
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('Đã gửi lệnh in qua $modeLabel')),
            );
        }
      },
      builder: (context, state) {
        final invoice = state.currentInvoice;
        final isPrinting = state.status == InvoiceStatus.printing;
        final escPosConfig = _effectiveEscPosConfig;
        final thermalWidth = EscPosRasterPrinterService.targetWidthForPaperMm(
          escPosConfig.paperWidthMm,
        ).toDouble();

        return Scaffold(
          appBar: AppBar(
            title: Text(
              invoice != null
                  ? 'Hóa đơn ${invoice.orderCode}'
                  : 'Xem trước hóa đơn',
            ),
            actions: [
              if (widget.onOpenPrinterSettings != null)
                IconButton(
                  tooltip: 'Cấu hình máy in',
                  onPressed: widget.onOpenPrinterSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
            ],
          ),
          body: invoice == null
              ? const Center(
                  child: Text('Chưa có hóa đơn để hiển thị'),
                )
              : Column(
                  children: [
                    if (state.errorMessage != null &&
                        state.errorMessage!.isNotEmpty)
                      _PrintErrorBanner(
                        message: state.errorMessage!,
                        isPrinting: isPrinting,
                        onRetryEscPos: () =>
                            _handleEscPosPrint(context.read<InvoiceCubit>()),
                        onFallbackPdf: () => context
                            .read<InvoiceCubit>()
                            .printPdfCurrentInvoice(),
                        onOpenSettings: widget.onOpenPrinterSettings,
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: RepaintBoundary(
                                  key: _receiptBoundaryKey,
                                  child: SizedBox(
                                    width: thermalWidth,
                                    child: _ReceiptPaperView(invoice: invoice),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPrinting)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: LinearProgressIndicator(),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isPrinting
                                        ? null
                                        : () => _handleEscPosPrint(
                                              context.read<InvoiceCubit>(),
                                            ),
                                    icon: const Icon(Icons.print_outlined),
                                    label: Text(
                                      state.errorMessage != null
                                          ? 'In lại (ESC/POS)'
                                          : 'In máy in nhiệt',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isPrinting
                                        ? null
                                        : () => context
                                            .read<InvoiceCubit>()
                                            .printPdfCurrentInvoice(),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: const Text('In PDF / Hệ thống'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PrintErrorBanner extends StatelessWidget {
  const _PrintErrorBanner({
    required this.message,
    required this.isPrinting,
    required this.onRetryEscPos,
    required this.onFallbackPdf,
    this.onOpenSettings,
  });

  final String message;
  final bool isPrinting;
  final VoidCallback onRetryEscPos;
  final VoidCallback onFallbackPdf;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: isPrinting ? null : onRetryEscPos,
                  child: const Text('In lại ESC/POS'),
                ),
                TextButton(
                  onPressed: isPrinting ? null : onFallbackPdf,
                  child: const Text('Chuyển sang In PDF'),
                ),
                if (onOpenSettings != null)
                  TextButton(
                    onPressed: isPrinting ? null : onOpenSettings,
                    child: const Text('Cấu hình máy in'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptPaperView extends StatelessWidget {
  const _ReceiptPaperView({required this.invoice});

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final localCreatedAt = invoice.createdAt.toLocal();
    final store = invoice.store;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.black,
          fontSize: 13,
          height: 1.35,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStoreHeader(store),
            const SizedBox(height: 10),
            const Divider(color: Colors.black54, thickness: 1),
            const SizedBox(height: 6),
            const Text(
              'HÓA ĐƠN BÁN HÀNG',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            _metaRow('Mã đơn:', invoice.orderCode),
            _metaRow('Ngày hóa đơn:', _dateFormat.format(localCreatedAt)),
            _metaRow('Thời gian tạo:', _timeFormat.format(localCreatedAt)),
            _metaRow('Nhân viên:', invoice.staffName),
            const SizedBox(height: 8),
            const Divider(color: Colors.black54, thickness: 1),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Mặt hàng',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'SL x Giá',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Thành tiền',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.black26, thickness: 1),
            ...invoice.items.map(_buildItemBlock),
            const Divider(color: Colors.black54, thickness: 1),
            _metaRow(
              'Tổng giá trị đơn:',
              CurrencyFormatter.formatVnd(invoice.subtotal),
            ),
            _metaRow(
              '% giảm giá:',
              '${_formatNumber(invoice.discountPercent)}%',
            ),
            _metaRow(
              'Tiền giảm:',
              CurrencyFormatter.formatVnd(invoice.discountAmount),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Flexible(
                  child: Text(
                    'Tổng cần thanh toán:',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  CurrencyFormatter.formatVnd(invoice.totalPayable),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _metaRow('Hình thức thanh toán:', invoice.paymentMethod),
            const SizedBox(height: 12),
            const Divider(color: Colors.black26, thickness: 1),
            const SizedBox(height: 6),
            const Text(
              'Cảm ơn quý khách và hẹn gặp lại!',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreHeader(InvoiceStore store) {
    final hasLogo = store.logoUrl != null && store.logoUrl!.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black87, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasLogo
              ? Image.network(
                  store.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.storefront_outlined,
                    color: Colors.black,
                  ),
                )
              : const Icon(
                  Icons.storefront_outlined,
                  color: Colors.black,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (store.phone.isNotEmpty) Text('SĐT: ${store.phone}'),
              if (store.address.isNotEmpty) Text('Đ/c: ${store.address}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemBlock(InvoiceItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  '${item.name} (${item.sku})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${_formatNumber(item.quantity)} ${item.unit}\nx ${CurrencyFormatter.formatVnd(item.unitPrice)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  CurrencyFormatter.formatVnd(item.lineTotal),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'CK: ${_formatNumber(item.discountPercent)}% (${CurrencyFormatter.formatVnd(item.discountAmount)}) • VAT: ${_formatNumber(item.vatRate)}% (${CurrencyFormatter.formatVnd(item.vatAmount)})',
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
          if (item.note.trim().isNotEmpty)
            Text(
              'Ghi chú: ${item.note.trim()}',
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
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
