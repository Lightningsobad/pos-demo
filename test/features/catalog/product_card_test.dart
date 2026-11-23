import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:demo_application/features/catalog/presentation/widgets/product_card.dart';
import 'package:demo_application/features/catalog/presentation/widgets/video_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  const sampleProduct = Product(
    id: 1,
    sku: 'SP-001',
    name: 'Cà phê sữa đá lon 240ml',
    unit: 'Lon',
    price: 18500,
    vatRate: 0.08,
  );

  const imageMedia = ProductMedia(
    productId: 1,
    mediaType: MediaType.image,
    mediaUrl: 'https://example.com/images/1.jpg',
    thumbnailUrl: 'https://example.com/thumbs/1.jpg',
    sizeBytes: 20480,
  );

  const videoMedia = ProductMedia(
    productId: 1,
    mediaType: MediaType.video,
    mediaUrl: 'https://example.com/videos/1.mp4',
    thumbnailUrl: 'https://example.com/thumbs/1-video.jpg',
    sizeBytes: 512000,
  );

  Widget wrapCard(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 185,
            height: 276,
            child: child,
          ),
        ),
      ),
    );
  }

  group('ProductCard', () {
    testWidgets(
      'displays Stream 1 metadata immediately with Shimmer placeholders while Stream 2 & 3 are loading',
      (tester) async {
        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.loading(),
              mediaStatus: const MediaLoadStatus.loading(),
              onAddToCart: () {},
            ),
          ),
        );

        expect(find.text('Cà phê sữa đá lon 240ml'), findsOneWidget);
        expect(find.textContaining('SP-001'), findsOneWidget);
        expect(find.textContaining('Lon'), findsOneWidget);
        expect(
          find.text(CurrencyFormatter.formatVnd(sampleProduct.price)),
          findsOneWidget,
        );
        expect(find.byType(Shimmer), findsNWidgets(2));
        expect(find.text('Hết hàng'), findsNothing);
        expect(find.text('Tồn: --'), findsNothing);
      },
    );

    testWidgets(
      'video product shows Play/Video badge without VideoPlayerController and opens VideoDetailDialog on tap',
      (tester) async {
        var videoBuilderCalled = false;

        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.loaded(12),
              mediaStatus: const MediaLoadStatus.loaded(videoMedia),
              onAddToCart: () {},
              imageBuilder: (_, url) => Container(
                key: ValueKey('img-$url'),
                color: Colors.grey.shade200,
              ),
              videoPreviewBuilder: (_, media) {
                videoBuilderCalled = true;
                return Container(
                  key: ValueKey('video-player-${media.mediaUrl}'),
                  color: Colors.black,
                );
              },
            ),
          ),
        );

        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
        expect(find.byType(VideoDetailDialog), findsNothing);
        expect(videoBuilderCalled, isFalse);

        await tester.tap(find.byKey(const Key('product-media-1')));
        await tester.pumpAndSettle();

        expect(find.byType(VideoDetailDialog), findsOneWidget);
        expect(videoBuilderCalled, isTrue);
        expect(
          find.byKey(ValueKey('video-player-${videoMedia.mediaUrl}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '+ Thêm invokes onAddToCart when stock is loading or > 0, and disables with Hết hàng when stock is 0',
      (tester) async {
        var addCount = 0;

        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.loading(),
              mediaStatus: const MediaLoadStatus.loaded(imageMedia),
              onAddToCart: () => addCount++,
              imageBuilder: (_, url) => const SizedBox.expand(),
            ),
          ),
        );

        await tester.tap(find.text('+ Thêm'));
        await tester.pump();
        expect(addCount, 1);

        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.loaded(15),
              mediaStatus: const MediaLoadStatus.loaded(imageMedia),
              onAddToCart: () => addCount++,
              imageBuilder: (_, url) => const SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Còn: 15'), findsOneWidget);
        await tester.tap(find.text('+ Thêm'));
        await tester.pump();
        expect(addCount, 2);

        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.loaded(0),
              mediaStatus: const MediaLoadStatus.loaded(imageMedia),
              onAddToCart: () => addCount++,
              imageBuilder: (_, url) => const SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hết hàng'), findsOneWidget);
        final addButton = tester.widget<FilledButton>(
          find.byKey(const Key('add-to-cart-1')),
        );
        expect(addButton.onPressed, isNull);

        await tester.tap(find.byKey(const Key('add-to-cart-1')));
        await tester.pump();
        expect(addCount, 2);
      },
    );

    testWidgets(
      'renders subtle fallback placeholders when Stream 2 & 3 emit error',
      (tester) async {
        var added = false;

        await tester.pumpWidget(
          wrapCard(
            ProductCard(
              product: sampleProduct,
              stockStatus: const StockLoadStatus.error(),
              mediaStatus: const MediaLoadStatus.error(),
              onAddToCart: () => added = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tồn: --'), findsOneWidget);
        expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);

        await tester.tap(find.byKey(const Key('add-to-cart-1')));
        await tester.pump();
        expect(added, isTrue);
      },
    );
  });
}
