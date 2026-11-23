import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/core/utils/pos_calculator.dart';
import 'package:demo_application/features/cart/data/datasources/cart_local_datasource.dart';
import 'package:demo_application/features/cart/data/repositories/cart_repository_impl.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_cubit.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/cart/presentation/pages/cart_page.dart';
import 'package:demo_application/features/cart/presentation/widgets/cart_item_edit_sheet.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  const sampleProductA = Product(
    id: 1,
    sku: 'SKU-001',
    name: 'Cà phê sữa đá',
    unit: 'Ly',
    price: 35000,
    vatRate: 10,
  );

  const sampleProductB = Product(
    id: 2,
    sku: 'SKU-002',
    name: 'Bánh mì thịt',
    unit: 'Ổ',
    price: 25000,
    vatRate: 5,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  CartCubit createCubit() {
    final dataSource = CartLocalDataSource(prefs: prefs);
    final repository = CartRepositoryImpl(localDataSource: dataSource);
    return CartCubit(repository: repository);
  }

  group('CartCubit', () {
    test(
      'addProduct twice increments quantity from 1 to 2 and recalculates summary',
      () async {
        final cubit = createCubit();
        addTearDown(cubit.close);

        await cubit.addProduct(sampleProductA);
        expect(cubit.state.items, hasLength(1));
        expect(cubit.state.items.first.quantity, 1);

        await cubit.addProduct(sampleProductA);
        expect(cubit.state.items, hasLength(1));

        final item = cubit.state.items.first;
        expect(item.quantity, 2);

        final expectedLine = PosCalculator.calculateLine(
          unitPrice: sampleProductA.price,
          quantity: 2,
          discountPercent: 0,
          vatRate: sampleProductA.vatRate,
        );
        expect(item.calculation, expectedLine);
        expect(cubit.state.summary.subtotal, expectedLine.lineTotal);
        expect(cubit.state.summary.totalPayable, expectedLine.lineTotal);
        expect(cubit.state.summary.totalQuantity, 2);
      },
    );

    test(
      'updateItem and setOrderDiscountPercent match PosCalculator and persist draft JSON',
      () async {
        final cubit = createCubit();
        addTearDown(cubit.close);

        await cubit.addProduct(sampleProductA);
        await cubit.addProduct(sampleProductB);
        await cubit.updateItem(
          sampleProductA.id,
          quantity: 3,
          discountPercent: 15,
          vatRate: 8,
          note: 'Ít đường, nhiều đá',
        );
        await cubit.setOrderDiscountPercent(5);
        await cubit.setStaffName(AppSettings.sampleStaffNames[1]);
        await cubit.setPaymentMethod('Chuyển khoản');

        final expectedLineA = PosCalculator.calculateLine(
          unitPrice: sampleProductA.price,
          quantity: 3,
          discountPercent: 15,
          vatRate: 8,
        );
        final expectedLineB = PosCalculator.calculateLine(
          unitPrice: sampleProductB.price,
          quantity: 1,
          discountPercent: 0,
          vatRate: sampleProductB.vatRate,
        );
        final expectedOrder = PosCalculator.calculateOrder(
          lineTotals: [expectedLineA.lineTotal, expectedLineB.lineTotal],
          orderDiscountPercent: 5,
        );

        final itemA = cubit.state.items.firstWhere(
          (i) => i.productId == sampleProductA.id,
        );
        expect(itemA.quantity, 3);
        expect(itemA.discountPercent, 15);
        expect(itemA.vatRate, 8);
        expect(itemA.note, 'Ít đường, nhiều đá');
        expect(itemA.calculation, expectedLineA);

        expect(cubit.state.summary.subtotal, expectedOrder.subtotal);
        expect(
          cubit.state.summary.orderDiscountAmount,
          expectedOrder.discountAmount,
        );
        expect(cubit.state.summary.totalPayable, expectedOrder.totalPayable);
        expect(cubit.state.summary.totalQuantity, 4);

        // Restore in a fresh cubit backed by the same SharedPreferences.
        final restoredCubit = createCubit();
        addTearDown(restoredCubit.close);
        await restoredCubit.loadDraftCart();

        expect(restoredCubit.state.items, equals(cubit.state.items));
        expect(
          restoredCubit.state.orderDiscountPercent,
          cubit.state.orderDiscountPercent,
        );
        expect(restoredCubit.state.staffName, AppSettings.sampleStaffNames[1]);
        expect(restoredCubit.state.paymentMethod, 'Chuyển khoản');
        expect(restoredCubit.state.summary, equals(cubit.state.summary));
      },
    );

    test(
      'rejects discountPercent > 100, quantity <= 0, and non-finite inputs while preserving valid state',
      () async {
        final cubit = createCubit();
        addTearDown(cubit.close);

        await cubit.addProduct(sampleProductA);
        final validState = cubit.state;

        await cubit.updateItem(sampleProductA.id, discountPercent: 120);
        expect(cubit.state.items, equals(validState.items));
        expect(cubit.state.summary, equals(validState.summary));
        expect(cubit.state.errorMessage, isNotNull);
        final firstErrorNonce = cubit.state.errorNonce;
        expect(firstErrorNonce, greaterThan(0));

        await cubit.updateItem(sampleProductA.id, discountPercent: 120);
        expect(cubit.state.errorNonce, greaterThan(firstErrorNonce));

        await cubit.updateItem(sampleProductA.id, quantity: 0);
        expect(cubit.state.items, equals(validState.items));
        expect(cubit.state.errorNonce, greaterThan(firstErrorNonce + 1));

        await cubit.updateItem(sampleProductA.id, quantity: -2);
        expect(cubit.state.items, equals(validState.items));

        await cubit.updateItem(sampleProductA.id, vatRate: 105);
        expect(cubit.state.items, equals(validState.items));

        await cubit.setOrderDiscountPercent(101);
        expect(cubit.state.orderDiscountPercent, 0);
        expect(cubit.state.summary, equals(validState.summary));

        await cubit.setOrderDiscountPercent(double.nan);
        expect(cubit.state.orderDiscountPercent, 0);

        await cubit.updateItem(sampleProductA.id, quantity: double.infinity);
        expect(cubit.state.items, equals(validState.items));
      },
    );

    test('removeItem and clearCart update state and persisted draft', () async {
      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.addProduct(sampleProductA);
      await cubit.addProduct(sampleProductB);
      await cubit.removeItem(sampleProductA.id);

      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.items.first.productId, sampleProductB.id);

      await cubit.clearCart();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.orderDiscountPercent, 0);
      expect(cubit.state.summary.totalPayable, 0);

      final reloaded = createCubit();
      addTearDown(reloaded.close);
      await reloaded.loadDraftCart();
      expect(reloaded.state.items, isEmpty);
    });

    test('loadDraftCart falls back to empty cart on corrupt JSON', () async {
      await prefs.setString('pos_cart_draft_v1', '{not-valid-json');
      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.loadDraftCart();

      expect(cubit.state.status, CartStatus.ready);
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.summary.totalPayable, 0);
    });
  });

  group('CartPage & CartItemEditSheet', () {
    testWidgets(
      'displays totals, edits line item via sheet, edits order options, and triggers onCheckout',
      (tester) async {
        final cubit = createCubit();
        addTearDown(cubit.close);
        await cubit.addProduct(sampleProductA);

        CartState? checkedOutState;

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<CartCubit>.value(
              value: cubit,
              child: CartPage(
                onCheckout: (state) => checkedOutState = state,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Giỏ hàng POS'), findsOneWidget);
        expect(find.text('Cà phê sữa đá'), findsOneWidget);
        expect(find.text('Tổng giá trị đơn'), findsOneWidget);
        expect(find.text('Tiền giảm'), findsOneWidget);
        expect(find.text('Tổng cần thanh toán'), findsOneWidget);
        expect(find.text('Thanh toán & Xuất hóa đơn'), findsOneWidget);

        // Tap item card to open CartItemEditSheet.
        await tester.tap(find.text('Cà phê sữa đá'));
        await tester.pumpAndSettle();

        expect(find.byType(CartItemEditSheet), findsOneWidget);

        // Change quantity to 2, discount to 15%, VAT via quick chip 8%, note.
        await tester.enterText(
          find.byKey(const Key('cart_edit_quantity_field')),
          '2',
        );
        await tester.enterText(
          find.byKey(const Key('cart_edit_discount_field')),
          '15',
        );
        await tester.tap(find.text('8%'));
        await tester.enterText(
          find.byKey(const Key('cart_edit_note_field')),
          'Ghi chú thử nghiệm',
        );
        await tester.tap(find.text('Áp dụng'));
        await tester.pumpAndSettle();

        expect(find.byType(CartItemEditSheet), findsNothing);
        expect(cubit.state.items.first.quantity, 2);
        expect(cubit.state.items.first.discountPercent, 15);
        expect(cubit.state.items.first.vatRate, 8);
        expect(cubit.state.items.first.note, 'Ghi chú thử nghiệm');

        // Enter order discount 5% and select payment method 'Chuyển khoản'.
        await tester.enterText(
          find.byKey(const Key('cart_order_discount_field')),
          '5',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Chuyển khoản'));
        await tester.pumpAndSettle();

        final expectedLine = PosCalculator.calculateLine(
          unitPrice: sampleProductA.price,
          quantity: 2,
          discountPercent: 15,
          vatRate: 8,
        );
        final expectedOrder = PosCalculator.calculateOrder(
          lineTotals: [expectedLine.lineTotal],
          orderDiscountPercent: 5,
        );

        expect(
          find.text(CurrencyFormatter.formatVnd(expectedOrder.totalPayable)),
          findsOneWidget,
        );

        await tester.tap(find.text('Thanh toán & Xuất hóa đơn'));
        await tester.pumpAndSettle();

        expect(checkedOutState, isNotNull);
        expect(checkedOutState!.paymentMethod, 'Chuyển khoản');
        expect(
          checkedOutState!.summary.totalPayable,
          expectedOrder.totalPayable,
        );
      },
    );

    testWidgets(
      'renders CartItemCard without RenderFlex overflow at 320px width and long unit label',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final cubit = createCubit();
        addTearDown(cubit.close);

        await cubit.addProduct(
          const Product(
            id: 99,
            sku: 'SKU-LONG',
            name: 'Sản phẩm hộp lớn siêu dài',
            unit: 'Thùng 24 lon lớn',
            price: 185000,
            vatRate: 10,
          ),
        );
        await cubit.updateItem(99, discountPercent: 12.5);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<CartCubit>.value(
              value: cubit,
              child: const CartPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('CK 12.5%'), findsOneWidget);
        expect(find.text('VAT 10%'), findsOneWidget);
      },
    );

    testWidgets(
      'disables item cards, +/- buttons, clear cart, staff dropdown, discount field, and payment chips when isSubmitting is true',
      (tester) async {
        final cubit = createCubit();
        addTearDown(cubit.close);
        await cubit.addProduct(sampleProductA);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<CartCubit>.value(
              value: cubit,
              child: const CartPage(isSubmitting: true),
            ),
          ),
        );
        await tester.pump();

        // Tapping +/- and card must not alter quantity or open edit sheet.
        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await tester.tap(find.byIcon(Icons.remove_circle_outline));
        await tester.tap(find.text('Cà phê sữa đá'));
        await tester.tap(find.text('Xóa giỏ'));
        await tester.tap(find.text('Chuyển khoản'));
        await tester.pump();

        expect(find.byType(CartItemEditSheet), findsNothing);
        expect(cubit.state.items, hasLength(1));
        expect(cubit.state.items.first.quantity, 1);
        expect(cubit.state.paymentMethod, 'Tiền mặt');

        final discountField = tester.widget<TextField>(
          find.byKey(const Key('cart_order_discount_field')),
        );
        expect(discountField.enabled, isFalse);

        final staffDropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(staffDropdown.onChanged, isNull);
      },
    );

    testWidgets(
      'clearing order discount while focused keeps field empty until typing "10" and syncs "0" on blur',
      (tester) async {
        final cubit = createCubit();
        addTearDown(cubit.close);
        await cubit.addProduct(sampleProductA);

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<CartCubit>.value(
              value: cubit,
              child: const CartPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final fieldFinder = find.byKey(const Key('cart_order_discount_field'));
        await tester.tap(fieldFinder);
        await tester.pump();

        // Clear to empty while focused -> controller must stay empty, not revert to "0".
        await tester.enterText(fieldFinder, '');
        await tester.pump();
        expect(
          tester.widget<TextField>(fieldFinder).controller!.text,
          '',
        );

        // Typing "10" produces "10", not "010".
        await tester.enterText(fieldFinder, '10');
        await tester.pump();
        expect(
          tester.widget<TextField>(fieldFinder).controller!.text,
          '10',
        );
        expect(cubit.state.orderDiscountPercent, 10);

        // Clearing again then blurring restores "0".
        await tester.enterText(fieldFinder, '');
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(
          tester.widget<TextField>(fieldFinder).controller!.text,
          '0',
        );
      },
    );
  });
}
