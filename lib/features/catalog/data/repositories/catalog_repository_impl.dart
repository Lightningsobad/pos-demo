import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:dio/dio.dart';

/// Repository implementation delegating the 3 catalog streams to [CatalogRemoteDatasource].
class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl({required this._remoteDatasource});

  final CatalogRemoteDatasource _remoteDatasource;

  @override
  Future<CatalogPageResult> fetchProducts({
    required int page,
    int limit = AppConfig.catalogPageSize,
    String query = '',
    CancelToken? cancelToken,
  }) {
    return _remoteDatasource.fetchProducts(
      page: page,
      limit: limit,
      query: query,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<int> fetchProductStock(
    int productId, {
    CancelToken? cancelToken,
  }) {
    return _remoteDatasource.fetchProductStock(
      productId,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<ProductMedia> fetchProductMedia(
    int productId, {
    CancelToken? cancelToken,
  }) {
    return _remoteDatasource.fetchProductMedia(
      productId,
      cancelToken: cancelToken,
    );
  }
}
