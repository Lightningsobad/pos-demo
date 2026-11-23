import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:equatable/equatable.dart';

/// Progressive loading status for per-product Streams 2 and 3.
enum LoadStatus { loading, loaded, error }

/// Real-time stock status for a single catalog product (Stream 2).
class StockLoadStatus extends Equatable {
  const StockLoadStatus._({required this.status, this.stock});

  const StockLoadStatus.loading() : this._(status: LoadStatus.loading);

  const StockLoadStatus.loaded(int stock)
      : this._(status: LoadStatus.loaded, stock: stock);

  const StockLoadStatus.error() : this._(status: LoadStatus.error);

  final LoadStatus status;
  final int? stock;

  bool get isLoading => status == LoadStatus.loading;
  bool get isLoaded => status == LoadStatus.loaded;
  bool get isError => status == LoadStatus.error;

  @override
  List<Object?> get props => [status, stock];
}

/// Media metadata status for a single catalog product (Stream 3).
class MediaLoadStatus extends Equatable {
  const MediaLoadStatus._({required this.status, this.media});

  const MediaLoadStatus.loading() : this._(status: LoadStatus.loading);

  const MediaLoadStatus.loaded(ProductMedia media)
      : this._(status: LoadStatus.loaded, media: media);

  const MediaLoadStatus.error() : this._(status: LoadStatus.error);

  final LoadStatus status;
  final ProductMedia? media;

  bool get isLoading => status == LoadStatus.loading;
  bool get isLoaded => status == LoadStatus.loaded;
  bool get isError => status == LoadStatus.error;

  @override
  List<Object?> get props => [status, media];
}

/// Immutable state managed by [CatalogCubit].
class CatalogState extends Equatable {
  const CatalogState({
    this.products = const [],
    this.stockByProductId = const {},
    this.mediaByProductId = const {},
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.searchQuery = '',
    this.errorMessage,
  });

  final List<Product> products;
  final Map<int, StockLoadStatus> stockByProductId;
  final Map<int, MediaLoadStatus> mediaByProductId;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final String searchQuery;
  final String? errorMessage;

  CatalogState copyWith({
    List<Product>? products,
    Map<int, StockLoadStatus>? stockByProductId,
    Map<int, MediaLoadStatus>? mediaByProductId,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    bool? hasMore,
    String? searchQuery,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CatalogState(
      products: products ?? this.products,
      stockByProductId: stockByProductId ?? this.stockByProductId,
      mediaByProductId: mediaByProductId ?? this.mediaByProductId,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        products,
        stockByProductId,
        mediaByProductId,
        isLoadingInitial,
        isLoadingMore,
        hasMore,
        searchQuery,
        errorMessage,
      ];
}
