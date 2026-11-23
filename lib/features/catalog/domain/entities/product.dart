import 'package:equatable/equatable.dart';

/// Media asset type returned by Stream 3 (`/api/products/:id/media`).
enum MediaType { image, video }

/// Core product record returned by Stream 1 (`/api/products`).
class Product extends Equatable {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.unit,
    required this.price,
    required this.vatRate,
  });

  final int id;
  final String sku;
  final String name;
  final String unit;
  final double price;
  final double vatRate;

  @override
  List<Object?> get props => [id, sku, name, unit, price, vatRate];
}

/// Real-time stock payload returned by Stream 2 (`/api/products/:id/stock`).
class ProductStockResult extends Equatable {
  const ProductStockResult({
    required this.productId,
    required this.stock,
  });

  final int productId;
  final int stock;

  @override
  List<Object?> get props => [productId, stock];
}

/// Media metadata returned by Stream 3 (`/api/products/:id/media`).
class ProductMedia extends Equatable {
  const ProductMedia({
    required this.productId,
    required this.mediaType,
    required this.mediaUrl,
    required this.thumbnailUrl,
    required this.sizeBytes,
  });

  final int productId;
  final MediaType mediaType;
  final String mediaUrl;
  final String thumbnailUrl;
  final int sizeBytes;

  bool get isVideo => mediaType == MediaType.video;

  @override
  List<Object?> get props => [
        productId,
        mediaType,
        mediaUrl,
        thumbnailUrl,
        sizeBytes,
      ];
}

/// Paginated product list returned by Stream 1 (`/api/products`).
class CatalogPageResult extends Equatable {
  const CatalogPageResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<Product> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  @override
  List<Object?> get props => [items, page, limit, total, hasMore];
}
