import 'package:equatable/equatable.dart';

/// Result of calculating a single POS order line with per-step VND rounding.
class PosLineCalculation extends Equatable {
  const PosLineCalculation({
    required this.grossAmount,
    required this.discountAmount,
    required this.taxableAmount,
    required this.vatAmount,
    required this.lineTotal,
  });

  final double grossAmount;
  final double discountAmount;
  final double taxableAmount;
  final double vatAmount;
  final double lineTotal;

  @override
  List<Object?> get props => [
        grossAmount,
        discountAmount,
        taxableAmount,
        vatAmount,
        lineTotal,
      ];
}

/// Result of calculating POS order totals with per-step VND rounding.
class PosOrderCalculation extends Equatable {
  const PosOrderCalculation({
    required this.subtotal,
    required this.discountAmount,
    required this.totalPayable,
  });

  final double subtotal;
  final double discountAmount;
  final double totalPayable;

  @override
  List<Object?> get props => [subtotal, discountAmount, totalPayable];
}

/// POS pricing calculator matching backend `pricing.js` rounding and bounds.
abstract final class PosCalculator {
  static PosLineCalculation calculateLine({
    required double unitPrice,
    required double quantity,
    required double discountPercent,
    required double vatRate,
  }) {
    _requireMin(unitPrice, 0, 'unitPrice');
    _requireMin(quantity, 0, 'quantity', inclusive: false);
    _requirePercent(discountPercent, 'discountPercent');
    _requirePercent(vatRate, 'vatRate');

    // Match Node.js pricing.js operation order for identical IEEE-754 results.
    final grossAmount = unitPrice * quantity;
    final discountAmount = (grossAmount * (discountPercent / 100)).roundToDouble();
    final taxableAmount = grossAmount - discountAmount;
    final vatAmount = (taxableAmount * (vatRate / 100)).roundToDouble();
    final lineTotal = taxableAmount + vatAmount;

    return PosLineCalculation(
      grossAmount: grossAmount,
      discountAmount: discountAmount,
      taxableAmount: taxableAmount,
      vatAmount: vatAmount,
      lineTotal: lineTotal,
    );
  }

  static PosOrderCalculation calculateOrder({
    required List<double> lineTotals,
    required double orderDiscountPercent,
  }) {
    _requirePercent(orderDiscountPercent, 'orderDiscountPercent');

    var subtotal = 0.0;
    for (var i = 0; i < lineTotals.length; i++) {
      final lineTotal = lineTotals[i];
      _requireMin(lineTotal, 0, 'lineTotals[$i]');
      subtotal += lineTotal;
    }

    final discountAmount =
        (subtotal * (orderDiscountPercent / 100)).roundToDouble();
    final totalPayable = subtotal - discountAmount;

    return PosOrderCalculation(
      subtotal: subtotal,
      discountAmount: discountAmount,
      totalPayable: totalPayable,
    );
  }

  static void _requireMin(
    double value,
    double min,
    String name, {
    bool inclusive = true,
  }) {
    final validMin = inclusive ? value >= min : value > min;
    if (!value.isFinite || !validMin) {
      final bound = inclusive ? '>=' : '>';
      throw ArgumentError.value(value, name, 'Must be finite and $bound $min');
    }
  }

  static void _requirePercent(double value, String name) {
    if (!value.isFinite || value < 0 || value > 100) {
      throw ArgumentError.value(value, name, 'Must be finite and in [0, 100]');
    }
  }
}
