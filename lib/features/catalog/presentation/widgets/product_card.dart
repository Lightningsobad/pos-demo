import 'package:cached_network_image/cached_network_image.dart';
import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:demo_application/features/catalog/presentation/widgets/video_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Fixed-height Shopee-style product card displaying Stream 1 data immediately
/// while progressively fading in Stream 2 (stock) and Stream 3 (media).
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.stockStatus = const StockLoadStatus.loading(),
    this.mediaStatus = const MediaLoadStatus.loading(),
    this.onAddToCart,
    this.imageBuilder,
    this.videoPreviewBuilder,
  });

  static const double cardHeight = 276;
  static const double _mediaHeight = 122;

  final Product product;
  final StockLoadStatus stockStatus;
  final MediaLoadStatus mediaStatus;
  final VoidCallback? onAddToCart;

  /// Optional test hook to override remote image rendering without network I/O.
  final Widget Function(BuildContext context, String url)? imageBuilder;

  /// Optional test hook forwarded to [VideoDetailDialog].
  final Widget Function(BuildContext context, ProductMedia media)?
      videoPreviewBuilder;

  bool get _isOutOfStock =>
      stockStatus.status == LoadStatus.loaded && (stockStatus.stock ?? 0) <= 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMediaArea(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 34,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${product.sku} • ĐVT: ${product.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyFormatter.formatVnd(product.price),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFEE4D2D),
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildStockBadge(theme)),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 30,
                      child: FilledButton(
                        key: Key('add-to-cart-${product.id}'),
                        onPressed: _isOutOfStock ? null : onAddToCart,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEE4D2D),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('+ Thêm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaArea(BuildContext context) {
    final status = mediaStatus.status;
    final media = mediaStatus.media;

    if (status == LoadStatus.loading) {
      return SizedBox(
        key: Key('product-media-${product.id}'),
        height: _mediaHeight,
        child: const _MediaShimmerPlaceholder(),
      );
    }

    if (status == LoadStatus.error || media == null) {
      return SizedBox(
        key: Key('product-media-${product.id}'),
        height: _mediaHeight,
        child: const _MediaErrorPlaceholder(),
      );
    }

    final imageWidget = imageBuilder != null
        ? imageBuilder!(context, media.thumbnailUrl)
        : CachedNetworkImage(
            imageUrl: media.thumbnailUrl,
            memCacheWidth: 300,
            fadeInDuration: const Duration(milliseconds: 200),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, _) => const _MediaShimmerPlaceholder(),
            errorWidget: (_, _, _) => const _MediaErrorPlaceholder(),
          );

    final mediaContent = Stack(
      fit: StackFit.expand,
      children: [
        imageWidget,
        if (media.isVideo) ...[
          Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(175),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
                  SizedBox(width: 3),
                  Text(
                    'Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    if (!media.isVideo) {
      return SizedBox(
        key: Key('product-media-${product.id}'),
        height: _mediaHeight,
        child: mediaContent,
      );
    }

    return SizedBox(
      height: _mediaHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('product-media-${product.id}'),
          onTap: () => _openVideoDialog(context, media),
          child: mediaContent,
        ),
      ),
    );
  }

  void _openVideoDialog(BuildContext context, ProductMedia media) {
    showDialog<void>(
      context: context,
      builder: (_) => VideoDetailDialog(
        product: product,
        media: media,
        videoBuilder: videoPreviewBuilder,
      ),
    );
  }

  Widget _buildStockBadge(ThemeData theme) {
    final Widget badge;
    if (stockStatus.status == LoadStatus.loading) {
      badge = Shimmer.fromColors(
        key: const ValueKey('stock-loading'),
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height: 22,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
    } else if (stockStatus.status == LoadStatus.error) {
      badge = _StockPill(
        key: const ValueKey('stock-error'),
        label: 'Tồn: --',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        textColor: theme.colorScheme.onSurfaceVariant,
      );
    } else {
      final stock = stockStatus.stock ?? 0;
      badge = stock > 0
          ? _StockPill(
              key: ValueKey('stock-loaded-$stock'),
              label: 'Còn: $stock',
              backgroundColor: const Color(0xFFE8F5E9),
              textColor: const Color(0xFF1B5E20),
            )
          : const _StockPill(
              key: ValueKey('stock-empty'),
              label: 'Hết hàng',
              backgroundColor: Color(0xFFFFEBEE),
              textColor: Color(0xFFB71C1C),
            );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: badge,
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MediaShimmerPlaceholder extends StatelessWidget {
  const _MediaShimmerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(color: Colors.white),
    );
  }
}

class _MediaErrorPlaceholder extends StatelessWidget {
  const _MediaErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: theme.colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
