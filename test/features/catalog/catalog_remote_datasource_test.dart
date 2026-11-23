import 'dart:async';
import 'dart:convert';

import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:demo_application/features/catalog/data/repositories/catalog_repository_impl.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

ResponseBody _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late _MockDioClient mockDioClient;
  late Dio dio;
  late CatalogRemoteDatasource datasource;
  late CatalogRepositoryImpl repository;
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        logs.add(message);
      }
    };

    dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    mockDioClient = _MockDioClient();
    when(() => mockDioClient.dio).thenReturn(dio);

    datasource = CatalogRemoteDatasource(dioClient: mockDioClient);
    repository = CatalogRepositoryImpl(remoteDatasource: datasource);
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  group('Catalog domain entities', () {
    test('support Equatable comparison and ProductMedia.isVideo', () {
      const productA = Product(
        id: 1,
        sku: 'SKU-001',
        name: 'Cà phê sữa đá',
        unit: 'Ly',
        price: 29000,
        vatRate: 8,
      );
      const productB = Product(
        id: 1,
        sku: 'SKU-001',
        name: 'Cà phê sữa đá',
        unit: 'Ly',
        price: 29000,
        vatRate: 8,
      );
      expect(productA, equals(productB));

      const stockResult = ProductStockResult(productId: 1, stock: 25);
      expect(
        stockResult,
        equals(const ProductStockResult(productId: 1, stock: 25)),
      );

      const imageMedia = ProductMedia(
        productId: 1,
        mediaType: MediaType.image,
        mediaUrl: 'http://localhost:3000/media/prod_1.png',
        thumbnailUrl: 'http://localhost:3000/media/prod_1.png',
        sizeBytes: 1234,
      );
      const videoMedia = ProductMedia(
        productId: 2,
        mediaType: MediaType.video,
        mediaUrl: 'http://localhost:3000/media/sample_promo.mp4',
        thumbnailUrl: 'http://localhost:3000/media/prod_2.png',
        sizeBytes: 56789,
      );
      expect(imageMedia.isVideo, isFalse);
      expect(videoMedia.isVideo, isTrue);

      const pageResult = CatalogPageResult(
        items: [productA],
        page: 1,
        limit: 10,
        total: 1,
        hasMore: false,
      );
      expect(
        pageResult,
        equals(
          const CatalogPageResult(
            items: [productB],
            page: 1,
            limit: 10,
            total: 1,
            hasMore: false,
          ),
        ),
      );
    });
  });

  group('CatalogRemoteDatasource - Stream 1 (fetchProducts)', () {
    test('parses paginated product response and sends query parameters',
        () async {
      RequestOptions? capturedOptions;
      final cancelToken = CancelToken();

      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        capturedOptions = options;
        return _jsonResponse({
          'items': [
            {
              'id': 1,
              'sku': 'SKU-001',
              'name': 'Cà phê sữa đá Size M',
              'unit': 'Ly',
              'price': 29000,
              'vatRate': 8,
            },
            {
              'id': 2,
              'sku': 'SKU-002',
              'name': 'Trà đào cam sả',
              'unit': 'Ly',
              'price': 35000.5,
              'vatRate': 10,
            },
          ],
          'page': 2,
          'limit': 10,
          'total': 25,
          'hasMore': true,
        });
      });

      final result = await repository.fetchProducts(
        page: 2,
        limit: 10,
        query: 'cà phê',
        cancelToken: cancelToken,
      );

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.path, '/api/products');
      expect(capturedOptions!.method, 'GET');
      expect(capturedOptions!.queryParameters, {
        'page': 2,
        'limit': 10,
        'q': 'cà phê',
      });
      expect(capturedOptions!.cancelToken, same(cancelToken));

      expect(result.page, 2);
      expect(result.limit, 10);
      expect(result.total, 25);
      expect(result.hasMore, isTrue);
      expect(result.items, const [
        Product(
          id: 1,
          sku: 'SKU-001',
          name: 'Cà phê sữa đá Size M',
          unit: 'Ly',
          price: 29000.0,
          vatRate: 8.0,
        ),
        Product(
          id: 2,
          sku: 'SKU-002',
          name: 'Trà đào cam sả',
          unit: 'Ly',
          price: 35000.5,
          vatRate: 10.0,
        ),
      ]);
      expect(logs.any((log) => log.contains('Stream 1')), isTrue);
    });

    test('propagates DioExceptionType.cancel cleanly when cancelled', () async {
      final cancelToken = CancelToken();
      final completer = Completer<ResponseBody>();

      dio.httpClientAdapter = _FakeHttpClientAdapter((
        options,
        _,
        cancelFuture,
      ) {
        cancelFuture?.whenComplete(() {
          if (!completer.isCompleted) {
            completer.completeError(
              DioException.requestCancelled(
                requestOptions: options,
                reason: 'cancelled by test',
              ),
            );
          }
        });
        return completer.future;
      });

      final future = repository.fetchProducts(
        page: 1,
        query: 'abc',
        cancelToken: cancelToken,
      );
      cancelToken.cancel('search superseded');

      await expectLater(
        future,
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having(CancelToken.isCancel, 'isCancel', isTrue),
        ),
      );
      expect(logs.any((log) => log.contains('CANCELLED')), isTrue);
    });
  });

  group('CatalogRemoteDatasource - Stream 2 (fetchProductStock)', () {
    test('returns stock and forwards CancelToken', () async {
      RequestOptions? capturedOptions;
      final cancelToken = CancelToken();

      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        capturedOptions = options;
        return _jsonResponse({'productId': 7, 'stock': 42});
      });

      final stock = await repository.fetchProductStock(
        7,
        cancelToken: cancelToken,
      );

      expect(stock, 42);
      expect(capturedOptions?.path, '/api/products/7/stock');
      expect(capturedOptions?.cancelToken, same(cancelToken));
      expect(logs.any((log) => log.contains('Stream 2')), isTrue);
    });

    test('propagates DioExceptionType.cancel cleanly when stock is cancelled',
        () async {
      final cancelToken = CancelToken();
      final completer = Completer<ResponseBody>();

      dio.httpClientAdapter = _FakeHttpClientAdapter((
        options,
        _,
        cancelFuture,
      ) {
        cancelFuture?.whenComplete(() {
          if (!completer.isCompleted) {
            completer.completeError(
              DioException.requestCancelled(
                requestOptions: options,
                reason: 'page disposed',
              ),
            );
          }
        });
        return completer.future;
      });

      final future = repository.fetchProductStock(
        7,
        cancelToken: cancelToken,
      );
      cancelToken.cancel('search reset');

      await expectLater(
        future,
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having(CancelToken.isCancel, 'isCancel', isTrue),
        ),
      );
      expect(logs.any((log) => log.contains('CANCELLED')), isTrue);
    });

    test('propagates real network DioException distinctly from cancel',
        () async {
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          message: 'Connection timed out',
        );
      });

      await expectLater(
        repository.fetchProductStock(7),
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.connectionTimeout)
              .having(CancelToken.isCancel, 'isCancel', isFalse),
        ),
      );
    });
  });

  group('CatalogRemoteDatasource - Stream 3 (fetchProductMedia)', () {
    test('parses image and video media payloads and forwards CancelToken',
        () async {
      RequestOptions? capturedOptions;
      final cancelToken = CancelToken();

      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        capturedOptions = options;
        return _jsonResponse({
          'productId': 12,
          'mediaType': 'video',
          'mediaUrl': 'http://localhost:3000/media/sample_promo.mp4',
          'thumbnailUrl': 'http://localhost:3000/media/prod_1.png',
          'sizeBytes': 245760,
        });
      });

      final media = await repository.fetchProductMedia(
        12,
        cancelToken: cancelToken,
      );

      expect(capturedOptions?.path, '/api/products/12/media');
      expect(capturedOptions?.cancelToken, same(cancelToken));
      expect(
        media,
        const ProductMedia(
          productId: 12,
          mediaType: MediaType.video,
          mediaUrl: 'http://localhost:3000/media/sample_promo.mp4',
          thumbnailUrl: 'http://localhost:3000/media/prod_1.png',
          sizeBytes: 245760,
        ),
      );
      expect(media.isVideo, isTrue);
      expect(logs.any((log) => log.contains('Stream 3')), isTrue);
    });

    test('parses image mediaType with isVideo == false', () async {
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, _, _) async {
        return _jsonResponse({
          'productId': 3,
          'mediaType': 'image',
          'mediaUrl': 'http://localhost:3000/media/prod_3.png',
          'thumbnailUrl': 'http://localhost:3000/media/prod_3.png',
          'sizeBytes': 1024,
        });
      });

      final media = await repository.fetchProductMedia(3);

      expect(media.mediaType, MediaType.image);
      expect(media.isVideo, isFalse);
      expect(media.sizeBytes, 1024);
    });

    test('propagates DioExceptionType.cancel cleanly when media is cancelled',
        () async {
      final cancelToken = CancelToken();
      final completer = Completer<ResponseBody>();

      dio.httpClientAdapter = _FakeHttpClientAdapter((
        options,
        _,
        cancelFuture,
      ) {
        cancelFuture?.whenComplete(() {
          if (!completer.isCompleted) {
            completer.completeError(
              DioException.requestCancelled(
                requestOptions: options,
                reason: 'media cancelled',
              ),
            );
          }
        });
        return completer.future;
      });

      final future = repository.fetchProductMedia(
        12,
        cancelToken: cancelToken,
      );
      cancelToken.cancel('user scrolled away');

      await expectLater(
        future,
        throwsA(
          isA<DioException>()
              .having((e) => e.type, 'type', DioExceptionType.cancel)
              .having(CancelToken.isCancel, 'isCancel', isTrue),
        ),
      );
      expect(logs.any((log) => log.contains('CANCELLED')), isTrue);
    });
  });
}
