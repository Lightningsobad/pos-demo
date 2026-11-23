import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCatalogRepository extends Mock implements CatalogRepository {}

List<Product> _makePageProducts(int page, {int pageSize = 10}) {
  final startId = (page - 1) * pageSize + 1;
  return List.generate(pageSize, (index) {
    final id = startId + index;
    return Product(
      id: id,
      sku: 'SKU-$id',
      name: 'Sản phẩm $id',
      unit: 'Cái',
      price: 10000.0 + id * 1000,
      vatRate: 0.1,
    );
  });
}

ProductMedia _makeMedia(int productId) {
  return ProductMedia(
    productId: productId,
    mediaType: MediaType.image,
    mediaUrl: 'https://example.com/media/$productId.jpg',
    thumbnailUrl: 'https://example.com/thumb/$productId.jpg',
    sizeBytes: 2048,
  );
}

DioException _cancelException([String path = '/test']) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.cancel,
  );
}

void main() {
  late _MockCatalogRepository repository;

  setUpAll(() {
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    repository = _MockCatalogRepository();
  });

  group('CatalogCubit', () {
    test(
      'loadInitial emits Stream 1 products immediately while 10x Stream 2 & 10x Stream 3 run in parallel',
      () async {
        final page1 = _makePageProducts(1);
        final stockCompleters = {
          for (final p in page1) p.id: Completer<int>(),
        };
        final mediaCompleters = {
          for (final p in page1) p.id: Completer<ProductMedia>(),
        };

        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: page1,
            page: 1,
            limit: 10,
            total: 30,
            hasMore: true,
          ),
        );

        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          return stockCompleters[id]!.future;
        });

        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          return mediaCompleters[id]!.future;
        });

        final cubit = CatalogCubit(
          repository,
          scrollDebounceDuration: const Duration(milliseconds: 30),
        );
        addTearDown(cubit.close);

        await cubit.loadInitial();

        // Stream 1 should already be emitted while Stream 2 & 3 are still pending.
        expect(cubit.state.isLoadingInitial, isFalse);
        expect(cubit.state.products, page1);
        expect(cubit.state.hasMore, isTrue);
        for (final p in page1) {
          expect(
            cubit.state.stockByProductId[p.id],
            const StockLoadStatus.loading(),
          );
          expect(
            cubit.state.mediaByProductId[p.id],
            const MediaLoadStatus.loading(),
          );
          verify(
            () => repository.fetchProductStock(
              p.id,
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
          verify(
            () => repository.fetchProductMedia(
              p.id,
              cancelToken: any(named: 'cancelToken'),
            ),
          ).called(1);
        }

        // Complete all 10 stock & 10 media requests.
        for (final p in page1) {
          stockCompleters[p.id]!.complete(p.id * 5);
          mediaCompleters[p.id]!.complete(_makeMedia(p.id));
        }
        await Future<void>.delayed(Duration.zero);

        for (final p in page1) {
          expect(
            cubit.state.stockByProductId[p.id],
            StockLoadStatus.loaded(p.id * 5),
          );
          expect(
            cubit.state.mediaByProductId[p.id],
            MediaLoadStatus.loaded(_makeMedia(p.id)),
          );
        }
      },
    );

    test(
      'parallel Stream 2 & 3 latency equals ~1 request delay rather than 10x sequential delay',
      () async {
        final page1 = _makePageProducts(1);
        const singleDelay = Duration(milliseconds: 60);

        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: page1,
            page: 1,
            limit: 10,
            total: 10,
            hasMore: false,
          ),
        );

        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final id = invocation.positionalArguments.first as int;
          await Future<void>.delayed(singleDelay);
          return id * 2;
        });

        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final id = invocation.positionalArguments.first as int;
          await Future<void>.delayed(singleDelay);
          return _makeMedia(id);
        });

        final cubit = CatalogCubit(repository);
        addTearDown(cubit.close);

        final stopwatch = Stopwatch()..start();
        await cubit.loadInitial();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        stopwatch.stop();

        // Sequential 10x (or 20x) would take >= 600ms.
        expect(stopwatch.elapsedMilliseconds, lessThan(350));
        for (final p in page1) {
          expect(
            cubit.state.stockByProductId[p.id],
            StockLoadStatus.loaded(p.id * 2),
          );
          expect(
            cubit.state.mediaByProductId[p.id],
            MediaLoadStatus.loaded(_makeMedia(p.id)),
          );
        }
      },
    );

    test(
      'fast scroll jump from page 1 to page 5 cancels page 1 CancelToken and ignores DioExceptionType.cancel without error state',
      () async {
        final page1Tokens = <CancelToken>[];
        final page5Tokens = <CancelToken>[];
        final page1StockCompleters = <int, Completer<int>>{};
        final page1MediaCompleters = <int, Completer<ProductMedia>>{};

        when(
          () => repository.fetchProducts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final page = invocation.namedArguments[#page] as int;
          return CatalogPageResult(
            items: _makePageProducts(page),
            page: page,
            limit: 10,
            total: 60,
            hasMore: page < 6,
          );
        });

        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          final token = invocation.namedArguments[#cancelToken] as CancelToken;
          if (id <= 10) {
            page1Tokens.add(token);
            final completer = Completer<int>();
            page1StockCompleters[id] = completer;
            token.whenCancel.then((_) {
              if (!completer.isCompleted) {
                completer.completeError(_cancelException('/stock/$id'));
              }
            });
            return completer.future;
          }
          if (id >= 41 && id <= 50) {
            page5Tokens.add(token);
          }
          return Future.value(id * 10);
        });

        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          final token = invocation.namedArguments[#cancelToken] as CancelToken;
          if (id <= 10) {
            page1Tokens.add(token);
            final completer = Completer<ProductMedia>();
            page1MediaCompleters[id] = completer;
            token.whenCancel.then((_) {
              if (!completer.isCompleted) {
                completer.completeError(_cancelException('/media/$id'));
              }
            });
            return completer.future;
          }
          if (id >= 41 && id <= 50) {
            page5Tokens.add(token);
          }
          return Future.value(_makeMedia(id));
        });

        final cubit = CatalogCubit(
          repository,
          scrollDebounceDuration: const Duration(milliseconds: 40),
        );
        addTearDown(cubit.close);

        await cubit.loadInitial();
        await cubit.loadNextPage(); // page 2
        await cubit.loadNextPage(); // page 3
        await cubit.loadNextPage(); // page 4
        await cubit.loadNextPage(); // page 5

        expect(cubit.state.products, hasLength(50));
        expect(page1Tokens, isNotEmpty);
        expect(page1Tokens.every((t) => !t.isCancelled), isTrue);

        // Jump straight to page 5 (indices 40..49).
        cubit.onScrollPositionChanged(
          firstVisibleIndex: 40,
          lastVisibleIndex: 49,
        );

        // Wait past debounce duration.
        await Future<void>.delayed(const Duration(milliseconds: 80));

        // Page 1 CancelToken must have been cancelled, without setting error state.
        expect(page1Tokens.every((t) => t.isCancelled), isTrue);
        expect(cubit.state.errorMessage, isNull);
        for (var id = 1; id <= 10; id++) {
          expect(
            cubit.state.stockByProductId[id],
            const StockLoadStatus.loading(),
          );
          expect(
            cubit.state.mediaByProductId[id],
            const MediaLoadStatus.loading(),
          );
        }

        // Page 5 items should now be loaded after debounce.
        expect(page5Tokens, isNotEmpty);
        expect(page5Tokens.every((t) => !t.isCancelled), isTrue);
        for (var id = 41; id <= 50; id++) {
          expect(
            cubit.state.stockByProductId[id],
            StockLoadStatus.loaded(id * 10),
          );
          expect(
            cubit.state.mediaByProductId[id],
            MediaLoadStatus.loaded(_makeMedia(id)),
          );
        }

        // Scroll back to page 1 -> cancelled still-loading items re-fetch with new token.
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final id = invocation.positionalArguments.first as int;
          return id * 3;
        });
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final id = invocation.positionalArguments.first as int;
          return _makeMedia(id);
        });

        cubit.onScrollPositionChanged(
          firstVisibleIndex: 0,
          lastVisibleIndex: 5,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        for (var id = 1; id <= 10; id++) {
          expect(
            cubit.state.stockByProductId[id],
            StockLoadStatus.loaded(id * 3),
          );
        }
      },
    );

    test(
      'cubit.close() while Stream 2 & 3 requests are in-flight cancels tokens and prevents StateError when futures later settle',
      () async {
        final page1 = _makePageProducts(1);
        final stockCompleters = {
          for (final p in page1) p.id: Completer<int>(),
        };
        final mediaCompleters = {
          for (final p in page1) p.id: Completer<ProductMedia>(),
        };
        final capturedTokens = <CancelToken>[];

        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: page1,
            page: 1,
            limit: 10,
            total: 10,
            hasMore: false,
          ),
        );

        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          capturedTokens.add(
            invocation.namedArguments[#cancelToken] as CancelToken,
          );
          return stockCompleters[id]!.future;
        });

        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          capturedTokens.add(
            invocation.namedArguments[#cancelToken] as CancelToken,
          );
          return mediaCompleters[id]!.future;
        });

        final cubit = CatalogCubit(repository);
        await cubit.loadInitial();

        expect(capturedTokens, isNotEmpty);

        // Close while all 20 requests are still pending.
        await cubit.close();
        expect(capturedTokens.every((t) => t.isCancelled), isTrue);

        // Complete with both values and non-cancel errors after close -> must not throw StateError.
        for (final p in page1) {
          if (p.id.isEven) {
            stockCompleters[p.id]!.complete(10);
            mediaCompleters[p.id]!.complete(_makeMedia(p.id));
          } else {
            stockCompleters[p.id]!.completeError(Exception('late error'));
            mediaCompleters[p.id]!.completeError(Exception('late error'));
          }
        }
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'LRU cache evicts oldest page beyond default maxCachedPages (20 pages) and clears its stock/media entries',
      () async {
        when(
          () => repository.fetchProducts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final page = invocation.namedArguments[#page] as int;
          return CatalogPageResult(
            items: _makePageProducts(page),
            page: page,
            limit: 10,
            total: 250,
            hasMore: true,
          );
        });
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          return (invocation.positionalArguments.first as int) * 2;
        });
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          return _makeMedia(invocation.positionalArguments.first as int);
        });

        final cubit = CatalogCubit(repository);
        addTearDown(cubit.close);

        expect(AppConfig.catalogLruMaxPages, 20);

        await cubit.loadInitial(); // page 1
        for (var i = 0; i < 20; i++) {
          await cubit.loadNextPage(); // pages 2..21
        }
        await Future<void>.delayed(Duration.zero);

        // Retained: pages 2..21 -> 200 items, starting from product id 11.
        expect(cubit.state.products, hasLength(200));
        expect(cubit.state.products.first.id, 11);
        expect(cubit.state.products.last.id, 210);

        // Page 1 (ids 1..10) must be evicted from products, stockByProductId, and mediaByProductId.
        for (var id = 1; id <= 10; id++) {
          expect(cubit.state.products.any((p) => p.id == id), isFalse);
          expect(cubit.state.stockByProductId.containsKey(id), isFalse);
          expect(cubit.state.mediaByProductId.containsKey(id), isFalse);
        }
        expect(cubit.state.stockByProductId, hasLength(200));
        expect(cubit.state.mediaByProductId, hasLength(200));
      },
    );

    test(
      'LRU touch via onScrollPositionChanged preserves recently viewed page and evicts least-recently-used page',
      () async {
        when(
          () => repository.fetchProducts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final page = invocation.namedArguments[#page] as int;
          return CatalogPageResult(
            items: _makePageProducts(page),
            page: page,
            limit: 10,
            total: 60,
            hasMore: true,
          );
        });
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => 10);
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _makeMedia(invocation.positionalArguments.first as int),
        );

        final cubit = CatalogCubit(
          repository,
          maxCachedPages: 3,
          scrollDebounceDuration: const Duration(milliseconds: 20),
        );
        addTearDown(cubit.close);

        await cubit.loadInitial(); // page 1
        await cubit.loadNextPage(); // page 2
        await cubit.loadNextPage(); // page 3
        expect(cubit.state.products, hasLength(30));

        // Touch page 1 in viewport -> LRU order becomes [2, 3, 1].
        cubit.onScrollPositionChanged(
          firstVisibleIndex: 0,
          lastVisibleIndex: 4,
        );

        // Loading page 4 should evict page 2 (oldest unused), keeping pages 1, 3, 4 in sorted order.
        await cubit.loadNextPage();

        expect(cubit.state.products, hasLength(30));
        final retainedIds = cubit.state.products.map((p) => p.id).toList();
        expect(retainedIds, [
          for (var id = 1; id <= 10; id++) id,
          for (var id = 21; id <= 40; id++) id,
        ]);
        for (var id = 11; id <= 20; id++) {
          expect(cubit.state.stockByProductId.containsKey(id), isFalse);
          expect(cubit.state.mediaByProductId.containsKey(id), isFalse);
        }
      },
    );

    test(
      'onScrollPositionChanged triggers prefetch when lastVisibleIndex >= products.length - 3',
      () async {
        when(
          () => repository.fetchProducts(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) async {
          final page = invocation.namedArguments[#page] as int;
          return CatalogPageResult(
            items: _makePageProducts(page),
            page: page,
            limit: 10,
            total: 30,
            hasMore: page < 3,
          );
        });
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => 5);
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _makeMedia(invocation.positionalArguments.first as int),
        );

        final cubit = CatalogCubit(
          repository,
          scrollDebounceDuration: const Duration(milliseconds: 20),
        );
        addTearDown(cubit.close);

        await cubit.loadInitial();
        expect(cubit.state.products, hasLength(10));

        // Index 6 < 10 - 3 (7): should NOT trigger page 2.
        cubit.onScrollPositionChanged(
          firstVisibleIndex: 2,
          lastVisibleIndex: 6,
        );
        await Future<void>.delayed(Duration.zero);
        verifyNever(
          () => repository.fetchProducts(
            page: 2,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        );

        // Index 7 >= 10 - 3 (7): MUST trigger page 2 immediately.
        cubit.onScrollPositionChanged(
          firstVisibleIndex: 4,
          lastVisibleIndex: 7,
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        verify(
          () => repository.fetchProducts(
            page: 2,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(1);
        expect(cubit.state.products, hasLength(20));
      },
    );

    test(
      'decrementLocalStock decrements loaded stock, clamps at 0, and leaves non-loaded entries untouched',
      () async {
        final page1 = _makePageProducts(1).take(3).toList();
        final thirdStockCompleter = Completer<int>();

        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: page1,
            page: 1,
            limit: 10,
            total: 3,
            hasMore: false,
          ),
        );
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          final id = invocation.positionalArguments.first as int;
          if (id == 1) return Future.value(10);
          if (id == 2) return Future.value(2);
          return thirdStockCompleter.future;
        });
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _makeMedia(invocation.positionalArguments.first as int),
        );

        final cubit = CatalogCubit(repository);
        addTearDown(cubit.close);

        await cubit.loadInitial();
        await Future<void>.delayed(Duration.zero);

        cubit.decrementLocalStock({1: 3.0, 2: 5.0, 3: 1.0, 999: 2.0});

        expect(
          cubit.state.stockByProductId[1],
          const StockLoadStatus.loaded(7),
        );
        expect(
          cubit.state.stockByProductId[2],
          const StockLoadStatus.loaded(0),
        );
        expect(
          cubit.state.stockByProductId[3],
          const StockLoadStatus.loading(),
        );
        expect(cubit.state.stockByProductId.containsKey(999), isFalse);
      },
    );

    test(
      'non-cancel Stream 2/3 errors isolate to affected product without failing catalog',
      () async {
        final page1 = _makePageProducts(1).take(2).toList();
        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: any(named: 'query'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: page1,
            page: 1,
            limit: 10,
            total: 2,
            hasMore: false,
          ),
        );
        when(
          () => repository.fetchProductStock(
            1,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(Exception('stock service error'));
        when(
          () => repository.fetchProductStock(
            2,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => 42);
        when(
          () => repository.fetchProductMedia(
            1,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => _makeMedia(1));
        when(
          () => repository.fetchProductMedia(
            2,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(Exception('media service error'));

        final cubit = CatalogCubit(repository);
        addTearDown(cubit.close);

        await cubit.loadInitial();
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.products, hasLength(2));
        expect(cubit.state.stockByProductId[1], const StockLoadStatus.error());
        expect(
          cubit.state.stockByProductId[2],
          const StockLoadStatus.loaded(42),
        );
        expect(
          cubit.state.mediaByProductId[1],
          MediaLoadStatus.loaded(_makeMedia(1)),
        );
        expect(cubit.state.mediaByProductId[2], const MediaLoadStatus.error());
      },
    );

    blocTest<CatalogCubit, CatalogState>(
      'loadInitial emits loading then errorMessage when Stream 1 fails with non-cancel error',
      build: () {
        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: 'cà phê',
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenThrow(Exception('network timeout'));
        return CatalogCubit(repository);
      },
      act: (cubit) => cubit.loadInitial(query: 'cà phê'),
      expect: () => [
        const CatalogState(
          isLoadingInitial: true,
          searchQuery: 'cà phê',
        ),
        isA<CatalogState>()
            .having((s) => s.isLoadingInitial, 'isLoadingInitial', isFalse)
            .having((s) => s.searchQuery, 'searchQuery', 'cà phê')
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('network timeout'),
            ),
      ],
    );

    test(
      'loadInitial with new query cancels previous epoch tokens and discards stale responses',
      () async {
        final oldCompleter = Completer<CatalogPageResult>();
        final oldTokens = <CancelToken>[];

        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: 'old',
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((invocation) {
          oldTokens.add(invocation.namedArguments[#cancelToken] as CancelToken);
          return oldCompleter.future;
        });

        final newItems = _makePageProducts(2).take(2).toList();
        when(
          () => repository.fetchProducts(
            page: 1,
            limit: any(named: 'limit'),
            query: 'new',
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => CatalogPageResult(
            items: newItems,
            page: 1,
            limit: 10,
            total: 2,
            hasMore: false,
          ),
        );
        when(
          () => repository.fetchProductStock(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => 9);
        when(
          () => repository.fetchProductMedia(
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (invocation) async =>
              _makeMedia(invocation.positionalArguments.first as int),
        );

        final cubit = CatalogCubit(repository);
        addTearDown(cubit.close);

        unawaited(cubit.loadInitial(query: 'old'));
        await cubit.loadInitial(query: 'new');

        expect(oldTokens.single.isCancelled, isTrue);

        // Even if the old request resolves late without throwing cancel, it must be discarded.
        oldCompleter.complete(
          CatalogPageResult(
            items: _makePageProducts(1).take(1).toList(),
            page: 1,
            limit: 10,
            total: 1,
            hasMore: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.searchQuery, 'new');
        expect(cubit.state.products, newItems);
      },
    );
  });
}
