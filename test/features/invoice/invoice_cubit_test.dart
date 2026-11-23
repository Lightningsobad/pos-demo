import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:demo_application/features/cart/domain/entities/cart_summary.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/invoice/data/datasources/invoice_remote_datasource.dart';
import 'package:demo_application/features/invoice/data/repositories/invoice_repository_impl.dart';
import 'package:demo_application/features/invoice/data/services/pdf_invoice_service.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/repositories/invoice_repository.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_cubit.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_state.dart';
import 'package:demo_application/features/invoice/presentation/pages/invoice_history_page.dart';
import 'package:demo_application/features/invoice/presentation/pages/invoice_preview_page.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdf/widgets.dart' as pw;

class _MockInvoiceRepository extends Mock implements InvoiceRepository {}

class _MockPrinterService extends Mock implements PrinterService {}

class _MockDioClient extends Mock implements DioClient {}

typedef _AdapterHandler = Future<ResponseBody> Function(
  RequestOptions options,
  Stream<Uint8List>? requestStream,
  Future<void>? cancelFuture,
);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final _AdapterHandler _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options, requestStream, cancelFuture);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CreateOrderRequest(
        staffName: 'fallback',
        paymentMethod: 'Tiền mặt',
        discountPercent: 0,
        store: InvoiceStore(name: 'Demo', phone: '', address: ''),
        items: [],
      ),
    );
    registerFallbackValue(
      Invoice(
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
      ),
    );
    registerFallbackValue(const PrinterConfig());
    registerFallbackValue(Uint8List(0));
  });

  final sampleCartState = CartState(
    status: CartStatus.ready,
    staffName: 'Nguyễn Văn An',
    paymentMethod: 'Chuyển khoản',
    orderDiscountPercent: 5,
    items: const [
      CartItem(
        productId: 101,
        sku: 'SKU-101',
        name: 'Cà phê sữa đá',
        unit: 'Ly',
        unitPrice: 35000,
        quantity: 2,
        discountPercent: 10,
        vatRate: 8,
        note: 'Ít đường',
      ),
    ],
    summary: CartSummary.fromItems(
      const [
        CartItem(
          productId: 101,
          sku: 'SKU-101',
          name: 'Cà phê sữa đá',
          unit: 'Ly',
          unitPrice: 35000,
          quantity: 2,
          discountPercent: 10,
          vatRate: 8,
          note: 'Ít đường',
        ),
      ],
      orderDiscountPercent: 5,
    ),
  );

  const sampleStore = StoreConfig(
    name: 'Cửa hàng Demo POS',
    phone: '0901 234 567',
    address: '123 Nguyễn Huệ, Q.1, TP.HCM',
    logoUrl: 'https://example.com/logo.png',
  );

  final sampleInvoice = Invoice(
    id: 42,
    orderCode: 'HD-20261123-0042',
    staffName: 'Nguyễn Văn An',
    paymentMethod: 'Chuyển khoản',
    subtotal: 68040,
    discountPercent: 5,
    discountAmount: 3402,
    totalPayable: 64638,
    store: const InvoiceStore(
      name: 'Cửa hàng Demo POS',
      phone: '0901 234 567',
      address: '123 Nguyễn Huệ, Q.1, TP.HCM',
      logoUrl: 'https://example.com/logo.png',
    ),
    createdAt: DateTime.utc(2026, 11, 23, 4, 15, 30),
    items: const [
      InvoiceItem(
        productId: 101,
        sku: 'SKU-101',
        name: 'Cà phê sữa đá',
        unit: 'Ly',
        quantity: 2,
        unitPrice: 35000,
        discountPercent: 10,
        discountAmount: 7000,
        vatRate: 8,
        vatAmount: 5040,
        lineTotal: 68040,
        note: 'Ít đường',
      ),
    ],
  );

  group('InvoiceCubit (Review Focus #5)', () {
    late _MockInvoiceRepository mockRepo;
    late _MockPrinterService mockPrinter;
    late InvoiceCubit cubit;

    setUp(() {
      mockRepo = _MockInvoiceRepository();
      mockPrinter = _MockPrinterService();
      cubit = InvoiceCubit(
        repository: mockRepo,
        printerService: mockPrinter,
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test(
      'submitOrderAndOpenPreview calls POST /api/orders once, preserves currentInvoice on ESC/POS failure, and switches to PDF without re-submitting',
      () async {
        when(() => mockRepo.createOrder(any()))
            .thenAnswer((_) async => sampleInvoice);

        final created = await cubit.submitOrderAndOpenPreview(
          cart: sampleCartState,
          store: sampleStore,
        );

        expect(created, equals(sampleInvoice));
        expect(cubit.state.status, InvoiceStatus.ready);
        expect(cubit.state.currentInvoice, equals(sampleInvoice));
        verify(() => mockRepo.createOrder(any())).called(1);

        // Simulate ESC/POS thermal printer offline / timeout error.
        when(
          () => mockPrinter.printEscPos(
            invoice: any(named: 'invoice'),
            config: any(named: 'config'),
            receiptPngBytes: any(named: 'receiptPngBytes'),
          ),
        ).thenThrow(const SocketException('Connection timed out'));

        final escPosSuccess = await cubit.printCurrentInvoice(
          const PrinterConfig(
            mode: PrinterMode.escPosLan,
            lanIp: '192.168.1.200',
            lanPort: 9100,
          ),
          capturePng: () async => Uint8List.fromList([1, 2, 3, 4]),
        );

        expect(escPosSuccess, isFalse);
        expect(cubit.state.status, InvoiceStatus.ready);
        expect(cubit.state.currentInvoice, equals(sampleInvoice));
        expect(cubit.state.errorMessage, isNotNull);
        expect(cubit.state.errorNonce, 1);

        // Switching to PDF / Android Print does NOT call createOrder again.
        when(() => mockPrinter.printPdf(invoice: any(named: 'invoice')))
            .thenAnswer((_) async {});

        final pdfSuccess = await cubit.printPdfCurrentInvoice();

        expect(pdfSuccess, isTrue);
        expect(cubit.state.status, InvoiceStatus.ready);
        expect(cubit.state.currentInvoice, equals(sampleInvoice));
        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.lastPrintedMode, PrinterMode.pdfSystem);
        expect(cubit.state.printSuccessNonce, 1);

        verifyNoMoreInteractions(mockRepo);
      },
    );

    test('loadHistory loads orders and selectInvoice updates currentInvoice', () async {
      when(() => mockRepo.fetchOrders(limit: 20))
          .thenAnswer((_) async => [sampleInvoice]);

      await cubit.loadHistory();

      expect(cubit.state.isLoadingHistory, isFalse);
      expect(cubit.state.history, equals([sampleInvoice]));

      cubit.selectInvoice(sampleInvoice);
      expect(cubit.state.currentInvoice, equals(sampleInvoice));
      expect(cubit.state.status, InvoiceStatus.ready);
    });
  });

  group('InvoiceRemoteDatasource & InvoiceRepositoryImpl', () {
    test('createOrder posts exact payload to /api/orders and parses 201 invoice', () async {
      late RequestOptions capturedOptions;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        capturedOptions = options;
        return ResponseBody.fromString(
          jsonEncode({
            'id': 42,
            'orderCode': 'HD-20261123-0042',
            'staffName': 'Nguyễn Văn An',
            'paymentMethod': 'Chuyển khoản',
            'subtotal': 68040,
            'discountPercent': 5,
            'discountAmount': 3402,
            'totalPayable': 64638,
            'store': {
              'name': 'Cửa hàng Demo POS',
              'phone': '0901 234 567',
              'address': '123 Nguyễn Huệ, Q.1, TP.HCM',
              'logoUrl': 'https://example.com/logo.png',
            },
            'createdAt': '2026-11-23T04:15:30.000Z',
            'items': [
              {
                'productId': 101,
                'sku': 'SKU-101',
                'name': 'Cà phê sữa đá',
                'unit': 'Ly',
                'quantity': 2,
                'unitPrice': 35000,
                'discountPercent': 10,
                'discountAmount': 7000,
                'vatRate': 8,
                'vatAmount': 5040,
                'lineTotal': 68040,
                'note': 'Ít đường',
              },
            ],
          }),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final mockDioClient = _MockDioClient();
      when(() => mockDioClient.dio).thenReturn(dio);

      final repo = InvoiceRepositoryImpl(
        remoteDatasource: InvoiceRemoteDatasource(dioClient: mockDioClient),
      );

      final request = CreateOrderRequest.fromCart(
        cart: sampleCartState,
        store: sampleStore,
      );
      final invoice = await repo.createOrder(request);

      expect(capturedOptions.method, 'POST');
      expect(capturedOptions.path, '/api/orders');
      expect(capturedOptions.data['staffName'], 'Nguyễn Văn An');
      expect(capturedOptions.data['items'][0]['productId'], 101);
      expect(invoice, equals(sampleInvoice));
    });

    test('fetchOrders queries GET /api/orders?limit=20 and parses items', () async {
      late RequestOptions capturedOptions;
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        capturedOptions = options;
        return ResponseBody.fromString(
          jsonEncode({
            'items': [
              {
                'id': 42,
                'orderCode': 'HD-20261123-0042',
                'staffName': 'Nguyễn Văn An',
                'paymentMethod': 'Chuyển khoản',
                'subtotal': 68040,
                'discountPercent': 5,
                'discountAmount': 3402,
                'totalPayable': 64638,
                'store': {
                  'name': 'Cửa hàng Demo POS',
                  'phone': '0901 234 567',
                  'address': '123 Nguyễn Huệ, Q.1, TP.HCM',
                  'logoUrl': null,
                },
                'createdAt': '2026-11-23T04:15:30.000Z',
                'items': [],
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final mockDioClient = _MockDioClient();
      when(() => mockDioClient.dio).thenReturn(dio);

      final repo = InvoiceRepositoryImpl(
        remoteDatasource: InvoiceRemoteDatasource(dioClient: mockDioClient),
      );
      final orders = await repo.fetchOrders(limit: 20);

      expect(capturedOptions.method, 'GET');
      expect(capturedOptions.path, '/api/orders');
      expect(capturedOptions.queryParameters['limit'], 20);
      expect(orders, hasLength(1));
      expect(orders.first.orderCode, 'HD-20261123-0042');
    });
  });

  group('PdfInvoiceService', () {
    test('generates valid PDF bytes and invokes layoutPdfCallback offline', () async {
      String? layoutName;
      Uint8List? renderedBytes;

      final pdfService = PdfInvoiceService(
        loadRegularFont: () async => pw.Font.helvetica(),
        loadBoldFont: () async => pw.Font.helveticaBold(),
        layoutPdfCallback: ({required onLayout, required name}) async {
          layoutName = name;
          renderedBytes = await onLayout(PdfInvoiceService.defaultPageFormat);
          return true;
        },
      );

      await pdfService.printInvoice(sampleInvoice);

      expect(layoutName, 'HoaDon_${sampleInvoice.orderCode}');
      expect(renderedBytes, isNotNull);
      expect(renderedBytes!.length, greaterThan(100));
      expect(String.fromCharCodes(renderedBytes!.sublist(0, 4)), '%PDF');
    });
  });

  group('InvoicePreviewPage & InvoiceHistoryPage', () {
    testWidgets(
      'InvoicePreviewPage renders all receipt fields, preserves invoice on ESC/POS failure, and falls back to PDF',
      (tester) async {
        final mockRepo = _MockInvoiceRepository();
        final mockPrinter = _MockPrinterService();
        final cubit = InvoiceCubit(
          repository: mockRepo,
          printerService: mockPrinter,
        );
        addTearDown(cubit.close);

        final offlineLogoInvoice = Invoice(
          id: sampleInvoice.id,
          orderCode: sampleInvoice.orderCode,
          staffName: sampleInvoice.staffName,
          paymentMethod: sampleInvoice.paymentMethod,
          subtotal: sampleInvoice.subtotal,
          discountPercent: sampleInvoice.discountPercent,
          discountAmount: sampleInvoice.discountAmount,
          totalPayable: sampleInvoice.totalPayable,
          store: const InvoiceStore(
            name: 'Cửa hàng Demo POS',
            phone: '0901 234 567',
            address: '123 Nguyễn Huệ, Q.1, TP.HCM',
          ),
          createdAt: sampleInvoice.createdAt,
          items: sampleInvoice.items,
        );

        cubit.selectInvoice(offlineLogoInvoice);

        when(
          () => mockPrinter.printEscPos(
            invoice: any(named: 'invoice'),
            config: any(named: 'config'),
            receiptPngBytes: any(named: 'receiptPngBytes'),
          ),
        ).thenThrow(const SocketException('Printer offline'));
        when(() => mockPrinter.printPdf(invoice: any(named: 'invoice')))
            .thenAnswer((_) async {});

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<InvoiceCubit>.value(
              value: cubit,
              child: InvoicePreviewPage(
                printerConfig: const PrinterConfig(
                  mode: PrinterMode.escPosLan,
                  lanIp: '192.168.1.200',
                  paperWidthMm: 58,
                ),
                captureReceiptPng: (_, _) async => Uint8List.fromList([1, 2, 3]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cửa hàng Demo POS'), findsOneWidget);
        expect(find.text('HD-20261123-0042'), findsOneWidget);
        expect(find.text('Nguyễn Văn An'), findsOneWidget);
        expect(find.text('Cà phê sữa đá (SKU-101)'), findsOneWidget);
        expect(find.text('Ghi chú: Ít đường'), findsOneWidget);
        expect(find.text('Chuyển khoản'), findsOneWidget);

        // Tap ESC/POS print button -> fails but keeps invoice on screen.
        await tester.tap(find.text('In máy in nhiệt'));
        await tester.pumpAndSettle();

        expect(find.text('Chuyển sang In PDF'), findsOneWidget);
        expect(find.text('HD-20261123-0042'), findsOneWidget);

        // Dismiss the error SnackBar, then tap PDF fallback button -> succeeds without calling createOrder.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('In PDF / Hệ thống'));
        await tester.pumpAndSettle();

        verify(() => mockPrinter.printPdf(invoice: offlineLogoInvoice)).called(1);
        verifyNever(() => mockRepo.createOrder(any()));
      },
    );

    testWidgets(
      'InvoiceHistoryPage loads orders from GET /api/orders and opens preview on tap',
      (tester) async {
        final mockRepo = _MockInvoiceRepository();
        final mockPrinter = _MockPrinterService();
        final cubit = InvoiceCubit(
          repository: mockRepo,
          printerService: mockPrinter,
        );
        addTearDown(cubit.close);

        final offlineLogoInvoice = Invoice(
          id: sampleInvoice.id,
          orderCode: sampleInvoice.orderCode,
          staffName: sampleInvoice.staffName,
          paymentMethod: sampleInvoice.paymentMethod,
          subtotal: sampleInvoice.subtotal,
          discountPercent: sampleInvoice.discountPercent,
          discountAmount: sampleInvoice.discountAmount,
          totalPayable: sampleInvoice.totalPayable,
          store: const InvoiceStore(
            name: 'Cửa hàng Demo POS',
            phone: '0901 234 567',
            address: '123 Nguyễn Huệ, Q.1, TP.HCM',
          ),
          createdAt: sampleInvoice.createdAt,
          items: sampleInvoice.items,
        );

        when(() => mockRepo.fetchOrders(limit: 20))
            .thenAnswer((_) async => [offlineLogoInvoice]);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<InvoiceCubit>.value(
              value: cubit,
              child: const InvoiceHistoryPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('HD-20261123-0042'), findsOneWidget);

        await tester.tap(find.text('HD-20261123-0042'));
        await tester.pumpAndSettle();

        expect(find.text('Hóa đơn HD-20261123-0042'), findsOneWidget);
        expect(find.text('In máy in nhiệt'), findsOneWidget);
      },
    );
  });
}
