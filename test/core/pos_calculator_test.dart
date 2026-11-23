import 'package:demo_application/core/utils/pos_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosCalculator', () {
    test(
      'matches backend pricing.js for odd VND line discount, VAT, and order discount',
      () {
        final line = PosCalculator.calculateLine(
          unitPrice: 33333,
          quantity: 3,
          discountPercent: 15,
          vatRate: 8,
        );

        expect(line.grossAmount, 99999);
        expect(line.discountAmount, 15000);
        expect(line.taxableAmount, 84999);
        expect(line.vatAmount, 6800);
        expect(line.lineTotal, 91799);

        final order = PosCalculator.calculateOrder(
          lineTotals: [line.lineTotal],
          orderDiscountPercent: 5,
        );

        expect(order.subtotal, 91799);
        expect(order.discountAmount, 4590);
        expect(order.totalPayable, 87209);
      },
    );

    test('sums multiple lines with different VAT and discount rates', () {
      final line1 = PosCalculator.calculateLine(
        unitPrice: 25000,
        quantity: 2,
        discountPercent: 0,
        vatRate: 8,
      );
      final line2 = PosCalculator.calculateLine(
        unitPrice: 15000,
        quantity: 1,
        discountPercent: 10,
        vatRate: 0,
      );

      expect(line1.lineTotal, 54000);
      expect(line2.lineTotal, 13500);

      final order = PosCalculator.calculateOrder(
        lineTotals: [line1.lineTotal, line2.lineTotal],
        orderDiscountPercent: 0,
      );

      expect(order.subtotal, 67500);
      expect(order.discountAmount, 0);
      expect(order.totalPayable, 67500);
    });

    test('rounds half away from zero to match Math.round on positive VND', () {
      final line = PosCalculator.calculateLine(
        unitPrice: 250,
        quantity: 1,
        discountPercent: 1,
        vatRate: 0,
      );
      expect(line.discountAmount, 3);
      expect(line.lineTotal, 247);
    });

    test('returns zero totals when order has empty lineTotals', () {
      final order = PosCalculator.calculateOrder(
        lineTotals: const [],
        orderDiscountPercent: 10,
      );

      expect(order.subtotal, 0);
      expect(order.discountAmount, 0);
      expect(order.totalPayable, 0);
    });

    test('throws ArgumentError when quantity <= 0 or unitPrice < 0', () {
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 20000,
          quantity: 0,
          discountPercent: 0,
          vatRate: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 20000,
          quantity: -2,
          discountPercent: 0,
          vatRate: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: -1,
          quantity: 1,
          discountPercent: 0,
          vatRate: 8,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when percentages are outside [0, 100]', () {
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 20000,
          quantity: 1,
          discountPercent: 105,
          vatRate: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 20000,
          quantity: 1,
          discountPercent: -0.5,
          vatRate: 8,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 20000,
          quantity: 1,
          discountPercent: 0,
          vatRate: 101,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateOrder(
          lineTotals: const [10000],
          orderDiscountPercent: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateOrder(
          lineTotals: const [10000],
          orderDiscountPercent: 100.1,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for non-finite inputs or negative line totals', () {
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: double.nan,
          quantity: 1,
          discountPercent: 0,
          vatRate: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateLine(
          unitPrice: 1000,
          quantity: double.infinity,
          discountPercent: 0,
          vatRate: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateOrder(
          lineTotals: const [-100],
          orderDiscountPercent: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosCalculator.calculateOrder(
          lineTotals: const [double.infinity],
          orderDiscountPercent: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
