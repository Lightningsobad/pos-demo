import 'dart:async';
import 'dart:math' as math;

import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:demo_application/features/catalog/presentation/widgets/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

/// Shopee-style 2-column catalog grid with 300ms debounced search and
/// viewport-aware scroll tracking for progressive 3-stream loading.
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    this.onAddToCart,
    this.imageBuilder,
    this.videoPreviewBuilder,
  });

  final void Function(Product product)? onAddToCart;

  /// Optional test hook forwarded to [ProductCard].
  final Widget Function(BuildContext context, String url)? imageBuilder;

  /// Optional test hook forwarded to [ProductCard].
  final Widget Function(BuildContext context, ProductMedia media)?
      videoPreviewBuilder;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  static const int _crossAxisCount = 2;
  static const double _gridPadding = 10;
  static const double _gridSpacing = 10;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 300);

  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  Timer? _searchDebounceTimer;

  int _lastProductCount = 0;
  int _lastReportedFirst = -1;
  int _lastReportedLast = -1;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String rawQuery) {
    _searchDebounceTimer?.cancel();
    final trimmed = rawQuery.trim();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      _resetScrollTracking();
      context.read<CatalogCubit>().loadInitial(query: trimmed);
    });
  }

  void _submitSearchNow(String rawQuery) {
    _searchDebounceTimer?.cancel();
    _resetScrollTracking();
    context.read<CatalogCubit>().loadInitial(query: rawQuery.trim());
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    _resetScrollTracking();
    context.read<CatalogCubit>().loadInitial(query: '');
  }

  void _resetScrollTracking() {
    _lastReportedFirst = -1;
    _lastReportedLast = -1;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _reportViewportIfNeeded(
    ScrollMetrics metrics,
    int itemCount, {
    bool force = false,
  }) {
    if (itemCount <= 0 || metrics.viewportDimension <= 0) return;

    const rowExtent = ProductCard.cardHeight + _gridSpacing;
    final scrollOffset = math.max(0.0, metrics.pixels);
    final viewportHeight = metrics.viewportDimension;

    final firstRow = math.max(
      0,
      ((scrollOffset - _gridPadding - ProductCard.cardHeight) / rowExtent)
              .floor() +
          1,
    );
    final lastRow =
        ((scrollOffset + viewportHeight - _gridPadding - 0.001) / rowExtent)
            .floor();
    if (lastRow < firstRow) return;

    final firstIndex = (firstRow * _crossAxisCount).clamp(0, itemCount - 1);
    final lastIndex =
        ((lastRow + 1) * _crossAxisCount - 1).clamp(0, itemCount - 1);

    if (!force &&
        firstIndex == _lastReportedFirst &&
        lastIndex == _lastReportedLast) {
      return;
    }

    _lastReportedFirst = firstIndex;
    _lastReportedLast = lastIndex;
    context.read<CatalogCubit>().onScrollPositionChanged(
          firstVisibleIndex: firstIndex,
          lastVisibleIndex: lastIndex,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(context),
        Expanded(
          child: BlocBuilder<CatalogCubit, CatalogState>(
            builder: (context, state) {
              if (_lastProductCount != state.products.length) {
                _lastProductCount = state.products.length;
                _lastReportedFirst = -1;
                _lastReportedLast = -1;
              }

              if (state.isLoadingInitial && state.products.isEmpty) {
                return _buildSkeletonGrid();
              }

              if (state.errorMessage != null && state.products.isEmpty) {
                return _buildErrorState(context, state.searchQuery);
              }

              if (state.products.isEmpty) {
                return _buildEmptyState(context);
              }

              return Column(
                children: [
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification ||
                            notification is ScrollEndNotification) {
                          _reportViewportIfNeeded(
                            notification.metrics,
                            state.products.length,
                            force: notification is ScrollEndNotification,
                          );
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: () async {
                          _resetScrollTracking();
                          await context
                              .read<CatalogCubit>()
                              .loadInitial(query: state.searchQuery);
                        },
                        child: GridView.builder(
                          key: const Key('catalog-grid'),
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(_gridPadding),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _crossAxisCount,
                            mainAxisExtent: ProductCard.cardHeight,
                            crossAxisSpacing: _gridSpacing,
                            mainAxisSpacing: _gridSpacing,
                          ),
                          itemCount: state.products.length,
                          itemBuilder: (context, index) {
                            final product = state.products[index];
                            final stockStatus =
                                state.stockByProductId[product.id] ??
                                    const StockLoadStatus.loading();
                            final mediaStatus =
                                state.mediaByProductId[product.id] ??
                                    const MediaLoadStatus.loading();
                            return ProductCard(
                              key: ValueKey('product-card-${product.id}'),
                              product: product,
                              stockStatus: stockStatus,
                              mediaStatus: mediaStatus,
                              onAddToCart: widget.onAddToCart == null
                                  ? null
                                  : () => widget.onAddToCart!(product),
                              imageBuilder: widget.imageBuilder,
                              videoPreviewBuilder: widget.videoPreviewBuilder,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (state.isLoadingMore)
                    const LinearProgressIndicator(minHeight: 2),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          return TextField(
            key: const Key('catalog-search-field'),
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: _submitSearchNow,
            decoration: InputDecoration(
              hintText: 'Tìm tên sản phẩm hoặc mã SKU...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      key: const Key('catalog-search-clear'),
                      tooltip: 'Xóa tìm kiếm',
                      icon: const Icon(Icons.close),
                      onPressed: _clearSearch,
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(_gridPadding),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _crossAxisCount,
        mainAxisExtent: ProductCard.cardHeight,
        crossAxisSpacing: _gridSpacing,
        mainAxisSpacing: _gridSpacing,
      ),
      itemCount: 6,
      itemBuilder: (_, _) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Không tìm thấy sản phẩm phù hợp',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String query) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 52,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Không thể tải danh sách sản phẩm',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  context.read<CatalogCubit>().loadInitial(query: query),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
