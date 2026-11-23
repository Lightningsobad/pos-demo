import 'package:demo_application/core/utils/pos_calculator.dart';
import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:equatable/equatable.dart';

/// Aggregated POS cart totals computed via [PosCalculator].
class CartSummary extends Equatable {
  const CartSummary({
    this.subtotal = 0,
    this.orderDiscountPercent = 0,
    this.orderDiscountAmount = 0,
    this.totalPayable = 0,
    this.totalQuantity = 0,
  });

  factory CartSummary.fromItems(
    List<CartItem> items, {
    double orderDiscountPercent = 0,
  }) {
    final lineTotals = items
        .map((item) => item.calculation.lineTotal)
        .toList(growable: false);
    final order = PosCalculator.calculateOrder(
      lineTotals: lineTotals,
      orderDiscountPercent: orderDiscountPercent,
    );
    final totalQuantity =
        items.fold<double>(0, (sum, item) => sum + item.quantity);

    return CartSummary(
      subtotal: order.subtotal,
      orderDiscountPercent: orderDiscountPercent,
      orderDiscountAmount: order.discountAmount,
      totalPayable: order.totalPayable,
      totalQuantity: totalQuantity,
    );
  }

  final double subtotal;
  final double orderDiscountPercent;
  final double orderDiscountAmount;
  final double totalPayable;
  final double totalQuantity;

  @override
  List<Object?> get props => [
        subtotal,
        orderDiscountPercent,
        orderDiscountAmount,
        totalPayable,
        totalQuantity,
      ];
}
