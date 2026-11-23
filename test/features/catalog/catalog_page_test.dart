import 'package:bloc_test/bloc_test.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:demo_application/features/catalog/presentation/pages/catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shimmer/shimmer.dart';

class _MockCatalogCubit extends MockCubit<CatalogState>
    implements CatalogCubit {}

List<Product> _makeProducts(int count) {
  return List.generate(count, (i) {
    final id = i + 1;
    return Product(
      id: id,
      sku: 'SKU-$id',
      name: 'Sản phẩm $id',
      unit: 'Cái',
      price: 15000 + id * 1000,
      vatRate: 0.08,
    );
  });
}

void main() {
  late _MockCatalogCubit cubit;

  setUp(() {
    cubit = _MockCatalogCubit();
    when(() => cubit.loadInitial(query: any(named: 'query')))
        .thenAnswer((_) async {});
    when(
      () => cubit.onScrollPositionChanged(
        firstVisibleIndex: any(named: 'firstVisibleIndex'),
        lastVisibleIndex: any(named: 'lastVisibleIndex'),
      ),
    ).thenReturn(null);
  });

  Widget buildSubject({
    required CatalogState state,
    void Function(Product)? onAddToCart,
  }) {
    when(() => cubit.state).thenReturn(state);
    whenListen(cubit, Stream<CatalogState>.value(state), initialState: state);

    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<CatalogCubit>.value(
          value: cubit,
          child: CatalogPage(
            onAddToCart: onAddToCart,
            imageBuilder: (_, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  group('CatalogPage', () {
    testWidgets(
      'debounces search input by 300ms before calling loadInitial',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            state: CatalogState(
              products: _makeProducts(4),
              stockByProductId: {
                for (var i = 1; i <= 4; i++) i: const StockLoadStatus.loaded(5),
              },
              mediaByProductId: {
                for (var i = 1; i <= 4; i++)
                  i: MediaLoadStatus.loaded(
                    ProductMedia(
                      productId: i,
                      mediaType: MediaType.image,
                      mediaUrl: 'https://example.com/$i.jpg',
                      thumbnailUrl: 'https://example.com/t/$i.jpg',
                      sizeBytes: 1000,
                    ),
                  ),
              },
            ),
          ),
        );

        await tester.enterText(
          find.byKey(const Key('catalog-search-field')),
          'cà phê',
        );
        await tester.pump(const Duration(milliseconds: 200));
        verifyNever(() => cubit.loadInitial(query: 'cà phê'));

        await tester.pump(const Duration(milliseconds: 120));
        verify(() => cubit.loadInitial(query: 'cà phê')).called(1);
      },
    );

    testWidgets(
      'calculates and reports firstVisibleIndex and lastVisibleIndex on scroll',
      (tester) async {
        tester.view.physicalSize = const Size(400, 660);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final products = _makeProducts(20);
        await tester.pumpWidget(
          buildSubject(
            state: CatalogState(
              products: products,
              stockByProductId: {
                for (final p in products) p.id: const StockLoadStatus.loaded(8),
              },
              mediaByProductId: {
                for (final p in products)
                  p.id: MediaLoadStatus.loaded(
                    ProductMedia(
                      productId: p.id,
                      mediaType: MediaType.image,
                      mediaUrl: 'https://example.com/${p.id}.jpg',
                      thumbnailUrl: 'https://example.com/t/${p.id}.jpg',
                      sizeBytes: 1000,
                    ),
                  ),
              },
            ),
          ),
        );

        // Scroll past row 0 (10 top padding + 276 card + 10 spacing = 296px)
        await tester.drag(
          find.byKey(const Key('catalog-grid')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();

        final captured = verify(
          () => cubit.onScrollPositionChanged(
            firstVisibleIndex: captureAny(named: 'firstVisibleIndex'),
            lastVisibleIndex: captureAny(named: 'lastVisibleIndex'),
          ),
        ).captured;

        expect(captured.length, greaterThanOrEqualTo(2));
        final lastFirst = captured[captured.length - 2] as int;
        final lastLast = captured[captured.length - 1] as int;
        expect(lastFirst, 2);
        expect(lastLast, greaterThanOrEqualTo(5));
        expect(lastLast, lessThanOrEqualTo(7));
      },
    );

    testWidgets(
      'passes onAddToCart to ProductCard and renders clean commercial UI without technical metrics',
      (tester) async {
        final added = <Product>[];
        final products = _makeProducts(2);

        await tester.pumpWidget(
          buildSubject(
            state: CatalogState(
              products: products,
              stockByProductId: {
                1: const StockLoadStatus.loaded(4),
                2: const StockLoadStatus.loaded(0),
              },
              mediaByProductId: {
                1: const MediaLoadStatus.loaded(
                  ProductMedia(
                    productId: 1,
                    mediaType: MediaType.image,
                    mediaUrl: 'https://example.com/1.jpg',
                    thumbnailUrl: 'https://example.com/t/1.jpg',
                    sizeBytes: 1000,
                  ),
                ),
                2: const MediaLoadStatus.loading(),
              },
            ),
            onAddToCart: added.add,
          ),
        );

        await tester.tap(find.byKey(const Key('add-to-cart-1')));
        await tester.pump();
        expect(added, [products[0]]);

        expect(find.textContaining('Luồng'), findsNothing);
        expect(find.textContaining('Stream'), findsNothing);
        expect(find.textContaining('Cancel'), findsNothing);
      },
    );

    testWidgets(
      'shows shimmer skeleton when initial loading',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(state: const CatalogState(isLoadingInitial: true)),
        );
        expect(find.byType(Shimmer), findsWidgets);
      },
    );

    testWidgets(
      'shows retry button on initial error and calls loadInitial on tap',
      (tester) async {
        await tester.pumpWidget(
          buildSubject(
            state: const CatalogState(
              isLoadingInitial: false,
              errorMessage: 'Network error',
            ),
          ),
        );
        expect(find.text('Thử lại'), findsOneWidget);
        await tester.tap(find.text('Thử lại'));
        await tester.pump();
        verify(() => cubit.loadInitial(query: '')).called(1);
      },
    );

    testWidgets(
      'reports initial viewport post-frame on tall viewport without manual scroll',
      (tester) async {
        tester.view.physicalSize = const Size(500, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final products = _makeProducts(10);
        await tester.pumpWidget(
          buildSubject(
            state: CatalogState(
              products: products,
              hasMore: true,
            ),
          ),
        );
        await tester.pump();

        verify(
          () => cubit.onScrollPositionChanged(
            firstVisibleIndex: 0,
            lastVisibleIndex: 9,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'shows non-blocking bottom retry bar when pagination fails with existing products',
      (tester) async {
        when(() => cubit.loadNextPage()).thenAnswer((_) async {});

        final products = _makeProducts(4);
        await tester.pumpWidget(
          buildSubject(
            state: CatalogState(
              products: products,
              hasMore: true,
              errorMessage: 'Pagination failed',
            ),
          ),
        );

        expect(find.text('Sản phẩm 1'), findsOneWidget);
        expect(find.text('Không thể tải thêm sản phẩm'), findsOneWidget);

        await tester.tap(find.text('Thử lại'));
        await tester.pump();
        verify(() => cubit.loadNextPage()).called(1);
      },
    );
  });
}
