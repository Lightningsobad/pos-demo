import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit managing Shopee-style 3-stream catalog loading, LRU page caching,
/// viewport prefetching, parallel per-item concurrency, and request cancellation.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(
    this._repository, {
    int pageSize = AppConfig.catalogPageSize,
    int maxCachedPages = AppConfig.catalogLruMaxPages,
    Duration scrollDebounceDuration = AppConfig.searchDebounce,
  })  : assert(pageSize > 0),
        assert(maxCachedPages > 0),
        assert(!scrollDebounceDuration.isNegative),
        _pageSize = pageSize,
        _maxCachedPages = maxCachedPages,
        _scrollDebounceDuration = scrollDebounceDuration,
        super(const CatalogState());

  final CatalogRepository _repository;
  final int _pageSize;
  final int _maxCachedPages;
  final Duration _scrollDebounceDuration;

  final LinkedHashMap<int, List<Product>> _pageCache =
      LinkedHashMap<int, List<Product>>();
  final Map<int, int> _pageByProductId = <int, int>{};
  final Map<int, StockLoadStatus> _stockMap = <int, StockLoadStatus>{};
  final Map<int, MediaLoadStatus> _mediaMap = <int, MediaLoadStatus>{};
  final Map<int, CancelToken> _pageCancelTokens = <int, CancelToken>{};

  CancelToken? _listCancelToken;
  Timer? _scrollDebounceTimer;

  int _queryEpoch = 0;
  int _highestLoadedPage = 0;
  int _activeWindowMin = 0;
  int _activeWindowMax = 2;

  /// Loads page 1 for [query], emits Stream 1 immediately, then fires
  /// parallel Stream 2 (stock) and Stream 3 (media) requests for page 1.
  Future<void> loadInitial({String query = ''}) async {
    _queryEpoch++;
    final epoch = _queryEpoch;

    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = null;
    _cancelAllRequests();

    _pageCache.clear();
    _pageByProductId.clear();
    _stockMap.clear();
    _mediaMap.clear();
    _highestLoadedPage = 0;
    _activeWindowMin = 0;
    _activeWindowMax = 2;

    if (isClosed) return;
    emit(
      CatalogState(
        isLoadingInitial: true,
        searchQuery: query,
      ),
    );

    final listToken = CancelToken();
    _listCancelToken = listToken;

    try {
      final result = await _repository.fetchProducts(
        page: 1,
        limit: _pageSize,
        query: query,
        cancelToken: listToken,
      );
      if (isClosed || epoch != _queryEpoch) return;

      _storePage(result.page, result.items);
      _highestLoadedPage = result.page;

      emit(
        CatalogState(
          products: _buildOrderedProducts(),
          stockByProductId: Map.unmodifiable(_stockMap),
          mediaByProductId: Map.unmodifiable(_mediaMap),
          isLoadingInitial: false,
          isLoadingMore: false,
          hasMore: result.hasMore,
          searchQuery: query,
        ),
      );

      if (result.items.isNotEmpty) {
        _fetchPageStreams(result.page, result.items, epoch);
      }
    } catch (error) {
      if (isClosed || epoch != _queryEpoch) return;
      if (_isCancelError(error)) return;
      emit(
        state.copyWith(
          isLoadingInitial: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Appends the next product page (Stream 1), enforces LRU page limit,
  /// and fetches Stream 2 & 3 if the page lies inside the active window.
  Future<void> loadNextPage() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoadingInitial) {
      return;
    }

    final epoch = _queryEpoch;
    final nextPage = _highestLoadedPage + 1;

    emit(state.copyWith(isLoadingMore: true, clearError: true));

    final listToken = CancelToken();
    _listCancelToken = listToken;

    try {
      final result = await _repository.fetchProducts(
        page: nextPage,
        limit: _pageSize,
        query: state.searchQuery,
        cancelToken: listToken,
      );
      if (isClosed || epoch != _queryEpoch) return;

      final loadedPage = result.page;
      _highestLoadedPage = math.max(_highestLoadedPage, loadedPage);
      if (result.items.isNotEmpty) {
        _storePage(loadedPage, result.items);
      }

      emit(
        state.copyWith(
          products: _buildOrderedProducts(),
          stockByProductId: Map.unmodifiable(_stockMap),
          mediaByProductId: Map.unmodifiable(_mediaMap),
          isLoadingMore: false,
          hasMore: result.hasMore,
          clearError: true,
        ),
      );

      if (result.items.isNotEmpty && _isPageInRetentionWindow(loadedPage)) {
        _fetchPageStreams(loadedPage, result.items, epoch);
      }
    } catch (error) {
      if (isClosed || epoch != _queryEpoch) return;
      if (_isCancelError(error)) {
        emit(state.copyWith(isLoadingMore: false));
        return;
      }
      emit(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Tracks viewport visibility for LRU recency, prefetches near the tail,
  /// cancels out-of-window page tokens, and debounces Stream 2/3 fetches.
  void onScrollPositionChanged({
    required int firstVisibleIndex,
    required int lastVisibleIndex,
  }) {
    if (isClosed || state.products.isEmpty || lastVisibleIndex < 0) {
      return;
    }

    final start = firstVisibleIndex.clamp(0, state.products.length - 1);
    final end = lastVisibleIndex.clamp(0, state.products.length - 1);
    if (start > end) return;

    if (lastVisibleIndex >= state.products.length - 3 &&
        state.hasMore &&
        !state.isLoadingMore &&
        !state.isLoadingInitial) {
      unawaited(loadNextPage());
    }

    int? minActivePage;
    int? maxActivePage;
    final visiblePages = <int>{};
    for (var i = start; i <= end; i++) {
      final page = _pageByProductId[state.products[i].id];
      if (page == null) continue;
      visiblePages.add(page);
      if (minActivePage == null || page < minActivePage) minActivePage = page;
      if (maxActivePage == null || page > maxActivePage) maxActivePage = page;
    }

    if (minActivePage == null || maxActivePage == null) return;

    for (final page in visiblePages) {
      _touchPage(page);
    }

    _activeWindowMin = minActivePage - 1;
    _activeWindowMax = maxActivePage + 1;

    _cancelTokensOutsideWindow(_activeWindowMin, _activeWindowMax);

    final epoch = _queryEpoch;
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(_scrollDebounceDuration, () {
      if (isClosed || epoch != _queryEpoch) return;
      for (var page = _activeWindowMin; page <= _activeWindowMax; page++) {
        final items = _pageCache[page];
        if (items == null || items.isEmpty) continue;
        final existingToken = _pageCancelTokens[page];
        if (existingToken != null && !existingToken.isCancelled) continue;
        _fetchPageStreams(page, items, epoch);
      }
    });
  }

  /// Immediately adjusts cached stock after a local checkout succeeds.
  void decrementLocalStock(Map<int, double> soldQuantities) {
    if (isClosed || soldQuantities.isEmpty) return;

    var changed = false;
    for (final entry in soldQuantities.entries) {
      final current = _stockMap[entry.key];
      if (current == null || !current.isLoaded || current.stock == null) {
        continue;
      }
      final updated = math.max(0, current.stock! - entry.value.round());
      if (updated != current.stock) {
        _stockMap[entry.key] = StockLoadStatus.loaded(updated);
        changed = true;
      }
    }

    if (changed) {
      emit(state.copyWith(stockByProductId: Map.unmodifiable(_stockMap)));
    }
  }

  void _storePage(int page, List<Product> items) {
    _pageCache.remove(page);
    _pageCache[page] = List<Product>.unmodifiable(items);
    for (final product in items) {
      _pageByProductId[product.id] = page;
      _stockMap.putIfAbsent(product.id, () => const StockLoadStatus.loading());
      _mediaMap.putIfAbsent(product.id, () => const MediaLoadStatus.loading());
    }
    _evictOverflowPages();
  }

  void _touchPage(int page) {
    final items = _pageCache.remove(page);
    if (items != null) {
      _pageCache[page] = items;
    }
  }

  void _evictOverflowPages() {
    while (_pageCache.length > _maxCachedPages) {
      final oldestPage = _pageCache.keys.first;
      final evictedItems = _pageCache.remove(oldestPage);
      if (evictedItems != null) {
        for (final product in evictedItems) {
          if (_pageByProductId[product.id] == oldestPage) {
            _pageByProductId.remove(product.id);
            _stockMap.remove(product.id);
            _mediaMap.remove(product.id);
          }
        }
      }
      final token = _pageCancelTokens.remove(oldestPage);
      if (token != null && !token.isCancelled) {
        token.cancel('evicted from LRU cache');
      }
    }
  }

  List<Product> _buildOrderedProducts() {
    final sortedPages = _pageCache.keys.toList()..sort();
    return List<Product>.unmodifiable([
      for (final page in sortedPages) ...?_pageCache[page],
    ]);
  }

  bool _isPageInRetentionWindow(int page) {
    return page >= _activeWindowMin && page <= _activeWindowMax;
  }

  void _cancelTokensOutsideWindow(int minPage, int maxPage) {
    final outsidePages = _pageCancelTokens.keys
        .where((page) => page < minPage || page > maxPage)
        .toList();
    for (final page in outsidePages) {
      final token = _pageCancelTokens.remove(page);
      if (token != null && !token.isCancelled) {
        token.cancel('scrolled out of viewport');
      }
    }
  }

  void _fetchPageStreams(int page, List<Product> items, int epoch) {
    final stockProducts = <Product>[];
    final mediaProducts = <Product>[];

    for (final product in items) {
      final stockStatus = _stockMap[product.id];
      if (stockStatus == null || stockStatus.isLoading) {
        _stockMap[product.id] = const StockLoadStatus.loading();
        stockProducts.add(product);
      }
      final mediaStatus = _mediaMap[product.id];
      if (mediaStatus == null || mediaStatus.isLoading) {
        _mediaMap[product.id] = const MediaLoadStatus.loading();
        mediaProducts.add(product);
      }
    }

    if (stockProducts.isEmpty && mediaProducts.isEmpty) return;

    final existing = _pageCancelTokens[page];
    if (existing != null && !existing.isCancelled) return;

    final token = CancelToken();
    _pageCancelTokens[page] = token;

    final futures = <Future<void>>[
      for (final p in stockProducts)
        _runStreamRequest<int>(
          page: page,
          productId: p.id,
          token: token,
          epoch: epoch,
          request: () =>
              _repository.fetchProductStock(p.id, cancelToken: token),
          onSuccess: (stock) {
            _stockMap[p.id] = StockLoadStatus.loaded(stock);
            emit(state.copyWith(stockByProductId: Map.unmodifiable(_stockMap)));
          },
          onError: () {
            _stockMap[p.id] = const StockLoadStatus.error();
            emit(state.copyWith(stockByProductId: Map.unmodifiable(_stockMap)));
          },
        ),
      for (final p in mediaProducts)
        _runStreamRequest<ProductMedia>(
          page: page,
          productId: p.id,
          token: token,
          epoch: epoch,
          request: () =>
              _repository.fetchProductMedia(p.id, cancelToken: token),
          onSuccess: (media) {
            _mediaMap[p.id] = MediaLoadStatus.loaded(media);
            emit(state.copyWith(mediaByProductId: Map.unmodifiable(_mediaMap)));
          },
          onError: () {
            _mediaMap[p.id] = const MediaLoadStatus.error();
            emit(state.copyWith(mediaByProductId: Map.unmodifiable(_mediaMap)));
          },
        ),
    ];

    Future.wait(futures).whenComplete(() {
      if (identical(_pageCancelTokens[page], token)) {
        _pageCancelTokens.remove(page);
      }
    });
  }

  Future<void> _runStreamRequest<T>({
    required int page,
    required int productId,
    required CancelToken token,
    required int epoch,
    required Future<T> Function() request,
    required void Function(T value) onSuccess,
    required void Function() onError,
  }) async {
    try {
      final value = await request();
      if (isClosed || epoch != _queryEpoch) return;
      if (token.isCancelled || _pageByProductId[productId] != page) return;
      onSuccess(value);
    } catch (error) {
      if (_isCancelError(error)) return;
      if (isClosed || epoch != _queryEpoch) return;
      if (token.isCancelled || _pageByProductId[productId] != page) return;
      onError();
    }
  }

  bool _isCancelError(Object error) {
    return error is DioException &&
        (error.type == DioExceptionType.cancel || CancelToken.isCancel(error));
  }

  void _cancelAllRequests() {
    if (_listCancelToken != null && !_listCancelToken!.isCancelled) {
      _listCancelToken!.cancel('catalog reset');
    }
    _listCancelToken = null;
    for (final token in _pageCancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('catalog reset');
      }
    }
    _pageCancelTokens.clear();
  }

  @override
  Future<void> close() {
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = null;
    _cancelAllRequests();
    return super.close();
  }
}
