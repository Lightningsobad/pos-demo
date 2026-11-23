import 'dart:typed_data';

import 'package:demo_application/features/invoice/data/services/escpos_raster_printer_service.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('EscPosRasterPrinterService', () {
    test(
      'encodeBitmapToEscPos encodes 384x16 image with GS v 0 header and 768-byte MSB-first payload',
      () {
        final image = img.Image(width: 384, height: 16, numChannels: 4);
        // Fill white opaque background.
        img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

        // Row 0: set pixel x=0 (MSB -> 0x80) and x=7 (LSB -> 0x01) -> byte[0] = 0x81.
        image.setPixelRgba(0, 0, 0, 0, 0, 255);
        image.setPixelRgba(7, 0, 10, 10, 10, 255);
        // Row 0: set pixel x=8 -> byte[1] = 0x80.
        image.setPixelRgba(8, 0, 0, 0, 0, 255);
        // Row 15: set pixel x=383 -> last byte of payload (byte 767) = 0x01.
        image.setPixelRgba(383, 15, 0, 0, 0, 255);
        // Transparent dark pixel should NOT print (treated as white/paper).
        image.setPixelRgba(16, 0, 0, 0, 0, 0);

        final encoded = EscPosRasterPrinterService.encodeBitmapToEscPos(image);

        expect(
          encoded.sublist(0, 8),
          equals(<int>[0x1D, 0x76, 0x30, 0x00, 48, 0, 16, 0]),
        );
        expect(encoded.length, 8 + 48 * 16);

        final payload = encoded.sublist(8);
        expect(payload.length, 768);
        expect(payload[0], 0x81);
        expect(payload[1], 0x80);
        expect(payload[2], 0x00);
        expect(payload[767], 0x01);
      },
    );

    test(
      'buildPrintJobBytes wraps init ESC @ before raster and feed+cut GS V 66 0 after raster',
      () {
        final image = img.Image(width: 384, height: 16, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));

        final job = EscPosRasterPrinterService.buildPrintJobBytes(image);

        expect(job.sublist(0, 2), equals(<int>[0x1B, 0x40]));
        expect(
          job.sublist(2, 10),
          equals(<int>[0x1D, 0x76, 0x30, 0x00, 48, 0, 16, 0]),
        );
        expect(
          job.sublist(job.length - 7),
          equals(<int>[0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x00]),
        );
        expect(job.length, 2 + 8 + 768 + 7);
      },
    );

    test(
      'printEscPos dispatches resized raster bytes over LAN or Bluetooth sender',
      () async {
        String? capturedIp;
        int? capturedPort;
        Duration? capturedTimeout;
        List<int>? capturedLanBytes;

        String? capturedMac;
        List<int>? capturedBtBytes;

        final service = EscPosRasterPrinterService(
          tcpSender: (ip, port, bytes, timeout) async {
            capturedIp = ip;
            capturedPort = port;
            capturedLanBytes = bytes;
            capturedTimeout = timeout;
          },
          bluetoothSender: (mac, bytes) async {
            capturedMac = mac;
            capturedBtBytes = bytes;
          },
        );

        final source = img.Image(width: 100, height: 20, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
        final pngBytes = Uint8List.fromList(img.encodePng(source));

        final sampleInvoice = Invoice(
          id: 1,
          orderCode: 'HD-20261123-0001',
          staffName: 'Nguyễn Văn An',
          paymentMethod: 'Tiền mặt',
          subtotal: 35000,
          discountPercent: 0,
          discountAmount: 0,
          totalPayable: 35000,
          store: const InvoiceStore(
            name: 'Cửa hàng Demo POS',
            phone: '0901 234 567',
            address: '123 Nguyễn Huệ',
          ),
          createdAt: DateTime.utc(2026, 11, 23, 4, 0, 0),
          items: const [],
        );

        await service.printEscPos(
          invoice: sampleInvoice,
          config: const PrinterConfig(
            mode: PrinterMode.escPosLan,
            lanIp: '192.168.1.200',
            lanPort: 9100,
            paperWidthMm: 58,
          ),
          receiptPngBytes: pngBytes,
        );

        expect(capturedIp, '192.168.1.200');
        expect(capturedPort, 9100);
        expect(capturedTimeout, const Duration(seconds: 3));
        expect(capturedLanBytes, isNotNull);
        // 58mm -> 384px -> widthBytes = 48
        expect(capturedLanBytes!.sublist(2, 8), equals(<int>[0x1D, 0x76, 0x30, 0x00, 48, 0]));

        await service.printEscPos(
          invoice: sampleInvoice,
          config: const PrinterConfig(
            mode: PrinterMode.escPosBluetooth,
            bluetoothMac: 'AA:BB:CC:DD:EE:FF',
            paperWidthMm: 80,
          ),
          receiptPngBytes: pngBytes,
        );

        expect(capturedMac, 'AA:BB:CC:DD:EE:FF');
        expect(capturedBtBytes, isNotNull);
        // 80mm -> 576px -> widthBytes = 72
        expect(capturedBtBytes!.sublist(2, 8), equals(<int>[0x1D, 0x76, 0x30, 0x00, 72, 0]));
      },
    );

    test('printEscPos throws PrinterException when LAN IP or BT MAC is empty', () async {
      final service = EscPosRasterPrinterService(
        tcpSender: (_, _, _, _) async {},
        bluetoothSender: (_, _) async {},
      );
      final source = img.Image(width: 10, height: 10, numChannels: 4);
      final pngBytes = Uint8List.fromList(img.encodePng(source));

      final sampleInvoice = Invoice(
        id: 1,
        orderCode: 'HD-20261123-0001',
        staffName: 'An',
        paymentMethod: 'Tiền mặt',
        subtotal: 0,
        discountPercent: 0,
        discountAmount: 0,
        totalPayable: 0,
        store: const InvoiceStore(name: 'Demo', phone: '', address: ''),
        createdAt: DateTime.utc(2026, 11, 23),
        items: const [],
      );

      await expectLater(
        () => service.printEscPos(
          invoice: sampleInvoice,
          config: const PrinterConfig(mode: PrinterMode.escPosLan, lanIp: ''),
          receiptPngBytes: pngBytes,
        ),
        throwsA(isA<PrinterException>()),
      );

      await expectLater(
        () => service.printEscPos(
          invoice: sampleInvoice,
          config: const PrinterConfig(
            mode: PrinterMode.escPosBluetooth,
            bluetoothMac: '',
          ),
          receiptPngBytes: pngBytes,
        ),
        throwsA(isA<PrinterException>()),
      );
    });
  });
}
