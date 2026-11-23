import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:demo_application/features/invoice/data/services/pdf_invoice_service.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

typedef TcpSocketSender = Future<void> Function(
  String ip,
  int port,
  List<int> bytes,
  Duration timeout,
);

typedef BluetoothBytesSender = Future<void> Function(
  String macAddress,
  List<int> bytes,
);

/// Dual printer service handling ESC/POS raster thermal printing (LAN/Bluetooth) and PDF fallback.
class EscPosRasterPrinterService implements PrinterService {
  EscPosRasterPrinterService({
    PdfInvoiceService? pdfInvoiceService,
    TcpSocketSender? tcpSender,
    BluetoothBytesSender? bluetoothSender,
  })  : _pdfInvoiceService = pdfInvoiceService ?? PdfInvoiceService(),
        _tcpSender = tcpSender ?? _defaultTcpSender,
        _bluetoothSender = bluetoothSender ?? _defaultBluetoothSender;

  static const Duration tcpConnectTimeout = Duration(seconds: 3);

  final PdfInvoiceService _pdfInvoiceService;
  final TcpSocketSender _tcpSender;
  final BluetoothBytesSender _bluetoothSender;

  /// Returns thermal pixel width for 58mm (`384px`) or 80mm (`576px`) paper.
  static int targetWidthForPaperMm(int paperWidthMm) {
    return paperWidthMm <= 58 ? 384 : 576;
  }

  /// Encodes an [img.Image] into ESC/POS `GS v 0` 1-bit MSB-first monochrome raster bytes.
  static List<int> encodeBitmapToEscPos(img.Image image) {
    final width = image.width;
    final height = image.height;
    final widthBytes = (width + 7) ~/ 8;

    final xL = widthBytes & 0xFF;
    final xH = (widthBytes >> 8) & 0xFF;
    final yL = height & 0xFF;
    final yH = (height >> 8) & 0xFF;

    final bytes = <int>[
      0x1D,
      0x76,
      0x30,
      0x00,
      xL,
      xH,
      yL,
      yH,
    ];

    for (var y = 0; y < height; y++) {
      for (var byteX = 0; byteX < widthBytes; byteX++) {
        var byteVal = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = byteX * 8 + bit;
          if (x < width) {
            final pixel = image.getPixel(x, y);
            // Only opaque dark pixels burn onto thermal paper; transparent pixels stay white.
            final isDark = pixel.a >= 128 && pixel.luminance < 128;
            if (isDark) {
              byteVal |= 1 << (7 - bit);
            }
          }
        }
        bytes.add(byteVal);
      }
    }

    return bytes;
  }

  /// Wraps [encodeBitmapToEscPos] with `ESC @` init and `GS V 66 0` feed & partial cut.
  static List<int> buildPrintJobBytes(img.Image image) {
    return <int>[
      0x1B,
      0x40,
      ...encodeBitmapToEscPos(image),
      0x0A,
      0x0A,
      0x0A,
      0x1D,
      0x56,
      0x42,
      0x00,
    ];
  }

  /// Captures the receipt [RepaintBoundary] and resizes it to [targetWidthPx] PNG bytes.
  static Future<Uint8List> captureReceiptBitmap(
    GlobalKey repaintBoundaryKey, {
    required int targetWidthPx,
  }) async {
    final context = repaintBoundaryKey.currentContext;
    if (context == null) {
      throw const PrinterException(
        'Không tìm thấy vùng xem trước hóa đơn để chụp ảnh in',
      );
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw const PrinterException('Khung xem trước hóa đơn chưa sẵn sàng để in');
    }

    final boundaryWidth = renderObject.size.width;
    final pixelRatio =
        boundaryWidth > 0 ? (targetWidthPx / boundaryWidth).clamp(1.0, 3.0) : 1.0;

    final uiImage = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw const PrinterException('Không thể xuất ảnh PNG từ hóa đơn');
      }

      final decoded = img.decodePng(byteData.buffer.asUint8List());
      if (decoded == null) {
        throw const PrinterException('Không thể giải mã ảnh hóa đơn');
      }

      final resized = decoded.width == targetWidthPx
          ? decoded
          : img.copyResize(decoded, width: targetWidthPx);
      return Uint8List.fromList(img.encodePng(resized));
    } finally {
      uiImage.dispose();
    }
  }

  @override
  Future<void> printEscPos({
    required Invoice invoice,
    required PrinterConfig config,
    required Uint8List receiptPngBytes,
  }) async {
    final decoded = img.decodePng(receiptPngBytes);
    if (decoded == null) {
      throw const PrinterException('Dữ liệu ảnh hóa đơn không hợp lệ');
    }

    final targetWidthPx = targetWidthForPaperMm(config.paperWidthMm);
    final resized = decoded.width == targetWidthPx
        ? decoded
        : img.copyResize(decoded, width: targetWidthPx);
    final jobBytes = buildPrintJobBytes(resized);

    switch (config.mode) {
      case PrinterMode.escPosLan:
        final ip = config.lanIp.trim();
        if (ip.isEmpty) {
          throw const PrinterException('Chưa cấu hình địa chỉ IP máy in LAN');
        }
        if (config.lanPort <= 0 || config.lanPort > 65535) {
          throw const PrinterException('Cổng máy in LAN không hợp lệ');
        }
        await _tcpSender(ip, config.lanPort, jobBytes, tcpConnectTimeout);
      case PrinterMode.escPosBluetooth:
        final mac = config.bluetoothMac.trim();
        if (mac.isEmpty) {
          throw const PrinterException('Chưa chọn máy in Bluetooth');
        }
        await _bluetoothSender(mac, jobBytes);
      case PrinterMode.pdfSystem:
        throw const PrinterException(
          'Cấu hình hiện tại là PDF/Android Print, không phải ESC/POS',
        );
    }
  }

  @override
  Future<void> printPdf({required Invoice invoice}) {
    return _pdfInvoiceService.printInvoice(invoice);
  }

  static Future<void> _defaultTcpSender(
    String ip,
    int port,
    List<int> bytes,
    Duration timeout,
  ) async {
    final socket = await Socket.connect(ip, port, timeout: timeout);
    try {
      socket.add(bytes);
      await socket.flush().timeout(const Duration(seconds: 5));
    } finally {
      await socket.close();
    }
  }

  static Future<void> _defaultBluetoothSender(
    String macAddress,
    List<int> bytes,
  ) async {
    final alreadyConnected = await PrintBluetoothThermal.connectionStatus;
    if (!alreadyConnected) {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress,
      );
      if (!connected) {
        throw PrinterException(
          'Không thể kết nối máy in Bluetooth ($macAddress)',
        );
      }
    }

    final written = await PrintBluetoothThermal.writeBytes(bytes);
    if (!written) {
      throw const PrinterException(
        'Gửi dữ liệu in qua Bluetooth thất bại',
      );
    }
  }
}
