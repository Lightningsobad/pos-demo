import 'dart:typed_data';

import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';

/// Typed failure raised by thermal/PDF printing services.
class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dual printing interface supporting ESC/POS thermal raster and PDF system printing.
abstract interface class PrinterService {
  Future<void> printEscPos({
    required Invoice invoice,
    required PrinterConfig config,
    required Uint8List receiptPngBytes,
  });

  Future<void> printPdf({required Invoice invoice});
}
