import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:dio/dio.dart';

/// Contract for fetching catalog products, real-time stock, and media metadata.
abstract interface class CatalogRepository {
  Future<CatalogPageResult> fetchProducts({
    required int page,
    int limit = AppConfig.catalogPageSize,
    String query = '',
    CancelToken? cancelToken,
  });

  Future<int> fetchProductStock(
    int productId, {
    CancelToken? cancelToken,
  });

  Future<ProductMedia> fetchProductMedia(
    int productId, {
    CancelToken? cancelToken,
  });
}
