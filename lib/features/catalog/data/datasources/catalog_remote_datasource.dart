import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Remote datasource handling the 3 independent catalog HTTP streams with CancelToken support.
class CatalogRemoteDatasource {
  CatalogRemoteDatasource({required this._dioClient});

  final DioClient _dioClient;

  /// Stream 1: Fetch paginated product metadata without stock or media delays.
  Future<CatalogPageResult> fetchProducts({
    required int page,
    int limit = AppConfig.catalogPageSize,
    String query = '',
    CancelToken? cancelToken,
  }) {
    return _runTimed(
      streamLabel: 'Stream 1',
      target: 'GET /api/products (page=$page, limit=$limit, q="$query")',
      action: () async {
        final response = await _dioClient.dio.get<dynamic>(
          '/api/products',
          queryParameters: <String, dynamic>{
            'page': page,
            'limit': limit,
            'q': query,
          },
          cancelToken: cancelToken,
        );
        return _parseCatalogPage(_requireMap(response.data, '/api/products'));
      },
      summary: (result) =>
          '${result.items.length} items, total=${result.total}, hasMore=${result.hasMore}',
    );
  }

  /// Stream 2: Fetch real-time stock for a single product.
  Future<int> fetchProductStock(
    int productId, {
    CancelToken? cancelToken,
  }) {
    final path = '/api/products/$productId/stock';
    return _runTimed(
      streamLabel: 'Stream 2',
      target: 'GET $path',
      action: () async {
        final response = await _dioClient.dio.get<dynamic>(
          path,
          cancelToken: cancelToken,
        );
        final data = _requireMap(response.data, path);
        return (data['stock'] as num).toInt();
      },
      summary: (stock) => 'stock=$stock',
    );
  }

  /// Stream 3: Fetch media descriptor (image or video) for a single product.
  Future<ProductMedia> fetchProductMedia(
    int productId, {
    CancelToken? cancelToken,
  }) {
    final path = '/api/products/$productId/media';
    return _runTimed(
      streamLabel: 'Stream 3',
      target: 'GET $path',
      action: () async {
        final response = await _dioClient.dio.get<dynamic>(
          path,
          cancelToken: cancelToken,
        );
        return _parseProductMedia(_requireMap(response.data, path));
      },
      summary: (media) =>
          'type=${media.mediaType.name}, sizeBytes=${media.sizeBytes}',
    );
  }

  Future<T> _runTimed<T>({
    required String streamLabel,
    required String target,
    required Future<T> Function() action,
    required String Function(T result) summary,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      debugPrint(
        '[Catalog][$streamLabel] $target -> ${stopwatch.elapsedMilliseconds}ms (${summary(result)})',
      );
      return result;
    } on DioException catch (e) {
      stopwatch.stop();
      if (CancelToken.isCancel(e) || e.type == DioExceptionType.cancel) {
        debugPrint(
          '[Catalog][$streamLabel] CANCELLED $target (${stopwatch.elapsedMilliseconds}ms)',
        );
      } else {
        debugPrint(
          '[Catalog][$streamLabel] ERROR $target (${stopwatch.elapsedMilliseconds}ms): ${e.type} ${e.message ?? ''}',
        );
      }
      // Propagate DioException intact so Cubit distinguishes CancelToken from network errors.
      rethrow;
    }
  }

  static Map<String, dynamic> _requireMap(dynamic data, String path) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw FormatException('Unexpected response format for $path');
  }

  static CatalogPageResult _parseCatalogPage(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected items list in /api/products');
    }

    final items = rawItems
        .map((item) => _parseProduct(_requireMap(item, '/api/products.items')))
        .toList(growable: false);

    return CatalogPageResult(
      items: items,
      page: (json['page'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      hasMore: json['hasMore'] as bool,
    );
  }

  static Product _parseProduct(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] as num).toInt(),
      sku: json['sku'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String,
      price: (json['price'] as num).toDouble(),
      vatRate: (json['vatRate'] as num).toDouble(),
    );
  }

  static ProductMedia _parseProductMedia(Map<String, dynamic> json) {
    final rawType = (json['mediaType'] as String? ?? 'image').toLowerCase();
    return ProductMedia(
      productId: (json['productId'] as num).toInt(),
      mediaType: rawType == 'video' ? MediaType.video : MediaType.image,
      mediaUrl: json['mediaUrl'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
