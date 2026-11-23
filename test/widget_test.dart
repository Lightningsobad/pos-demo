import 'dart:typed_data';

import 'package:demo_application/app.dart';
import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/repositories/invoice_repository.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalogRepository implements CatalogRepository {
  int fetchProductsCalls = 0;
  final Map<int, int> stockByProductId = {1: 10, 2: 5};

  @override
  Future<CatalogPageResult> fetchProducts({
    required int page,
    int limit = 10,
    String query = '',
    CancelToken? cancelToken,
  }) async {
    fetchProductsCalls++;
    return const CatalogPageResult(
      items: [
        Product(
          id: 1,
          sku: 'CF-001',
          name: 'Cà phê sữa đá',
          unit: 'Ly',
          price: 29000,
          vatRate: 8,
        ),
        Product(
          id: 2,
          sku: 'TR-002',
          name: 'Trà đào cam sả',
          unit: 'Ly',
          price: 35000,
          vatRate: 8,
        ),
      ],
      page: 1,
      limit: 10,
      total: 2,
      hasMore: false,
    );
  }

  @override
  Future<int> fetchProductStock(int productId, {CancelToken? cancelToken}) async {
    return stockByProductId[productId] ?? 0;
  }

  @override
  Future<ProductMedia> fetchProductMedia(
    int productId, {
    CancelToken? cancelToken,
  }) async {
    return ProductMedia(
      productId: productId,
      mediaType: MediaType.image,
      mediaUrl: 'https://example.com/$productId.jpg',
      thumbnailUrl: 'https://example.com/$productId-thumb.jpg',
      sizeBytes: 1024,
    );
  }
}

class _FakeInvoiceRepository implements InvoiceRepository {
  final List<Invoice> createdOrders = [];
  int fetchOrdersCalls = 0;

  @override
  Future<Invoice> createOrder(CreateOrderRequest request) async {
    final invoice = Invoice(
      id: createdOrders.length + 1,
      orderCode: 'HD-2026-000${createdOrders.length + 1}',
      staffName: request.staffName,
      paymentMethod: request.paymentMethod,
      subtotal: 29000,
      discountPercent: request.discountPercent,
      discountAmount: 0,
      totalPayable: 29000,
      store: request.store,
      createdAt: DateTime(2026, 11, 23, 10, 30),
      items: const [
        InvoiceItem(
          productId: 1,
          sku: 'CF-001',
          name: 'Cà phê sữa đá',
          unit: 'Ly',
          quantity: 1,
          unitPrice: 29000,
          discountPercent: 0,
          discountAmount: 0,
          vatRate: 8,
          vatAmount: 2148,
          lineTotal: 29000,
        ),
      ],
    );
    createdOrders.insert(0, invoice);
    return invoice;
  }

  @override
  Future<List<Invoice>> fetchOrders({int limit = 20}) async {
    fetchOrdersCalls++;
    return List<Invoice>.unmodifiable(createdOrders);
  }
}

class _FakePrinterService implements PrinterService {
  @override
  Future<void> printEscPos({
    required Invoice invoice,
    required PrinterConfig config,
    required Uint8List receiptPngBytes,
  }) async {}

  @override
  Future<void> printPdf({required Invoice invoice}) async {}
}

void main() {
  testWidgets('PosDemoApp end-to-end smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dioClient = DioClient();
    final catalogRepo = _FakeCatalogRepository();
    final invoiceRepo = _FakeInvoiceRepository();
    final printerService = _FakePrinterService();

    await tester.pumpWidget(
      PosDemoApp(
        sharedPreferences: prefs,
        dioClient: dioClient,
        catalogRepository: catalogRepo,
        invoiceRepository: invoiceRepo,
        printerService: printerService,
        imageBuilder: (_, _) => const SizedBox.expand(),
      ),
    );
    await tester.pumpAndSettle();

    // Zero counter template remnants.
    expect(find.text('You have pushed the button this many times:'), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);

    // 4 navigation tabs render.
    expect(find.text('Sản phẩm'), findsOneWidget);
    expect(find.text('Giỏ hàng'), findsOneWidget);
    expect(find.text('Hóa đơn'), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);

    // Products load on startup after SettingsCubit loads.
    expect(catalogRepo.fetchProductsCalls, 1);
    expect(find.text('Cà phê sữa đá'), findsOneWidget);
    expect(find.text('Còn: 10'), findsOneWidget);

    // Add item to cart and verify badge updates.
    await tester.tap(find.byKey(const Key('add-to-cart-1')));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    // Switch to Cart tab and checkout.
    await tester.tap(find.text('Giỏ hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ hàng POS'), findsOneWidget);

    await tester.tap(find.text('Thanh toán & Xuất hóa đơn'));
    await tester.pumpAndSettle();

    // Invoice preview opens and cart is cleared.
    expect(invoiceRepo.createdOrders, hasLength(1));
    expect(find.text('Hóa đơn HD-2026-0001'), findsOneWidget);

    // Jump to printer settings from preview.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Cấu hình POS'), findsOneWidget);

    // Badge is cleared after checkout.
    expect(find.text('1'), findsNothing);

    // Local stock decremented to 9 immediately after checkout.
    await tester.tap(find.text('Sản phẩm'));
    await tester.pumpAndSettle();
    expect(find.text('Còn: 9'), findsOneWidget);

    // Switch back to Settings, update Server URL and save -> reloads catalog & updates DioClient.
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    final serverField = find.widgetWithText(TextFormField, 'http://10.0.2.2:3000');
    await tester.enterText(serverField, 'http://192.168.1.55:3000');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(dioClient.dio.options.baseUrl, 'http://192.168.1.55:3000');
    expect(catalogRepo.fetchProductsCalls, 2);

    // Switch to Invoice History tab -> loads history and opens preview on tap.
    await tester.tap(find.text('Hóa đơn'));
    await tester.pumpAndSettle();
    expect(invoiceRepo.fetchOrdersCalls, 1);
    expect(find.text('HD-2026-0001'), findsOneWidget);

    await tester.tap(find.text('HD-2026-0001'));
    await tester.pumpAndSettle();
    expect(find.text('Hóa đơn HD-2026-0001'), findsOneWidget);
  });
}
