import 'package:demo_application/core/utils/pos_calculator.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:equatable/equatable.dart';

/// Line item inside the POS cart with per-line discount, VAT, and note.
class CartItem extends Equatable {
  const CartItem({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.unitPrice,
    required this.quantity,
    this.discountPercent = 0,
    required this.vatRate,
    this.note = '',
  });

  factory CartItem.fromProduct(Product product, {double quantity = 1}) {
    return CartItem(
      productId: product.id,
      sku: product.sku,
      name: product.name,
      unit: product.unit,
      unitPrice: product.price,
      quantity: quantity,
      discountPercent: 0,
      vatRate: product.vatRate,
      note: '',
    );
  }

  final int productId;
  final String sku;
  final String name;
  final String unit;
  final double unitPrice;
  final double quantity;
  final double discountPercent;
  final double vatRate;
  final String note;

  PosLineCalculation get calculation => PosCalculator.calculateLine(
        unitPrice: unitPrice,
        quantity: quantity,
        discountPercent: discountPercent,
        vatRate: vatRate,
      );

  CartItem copyWith({
    int? productId,
    String? sku,
    String? name,
    String? unit,
    double? unitPrice,
    double? quantity,
    double? discountPercent,
    double? vatRate,
    String? note,
  }) {
    return CartItem(
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      discountPercent: discountPercent ?? this.discountPercent,
      vatRate: vatRate ?? this.vatRate,
      note: note ?? this.note,
    );
  }

  @override
  List<Object?> get props => [
        productId,
        sku,
        name,
        unit,
        unitPrice,
        quantity,
        discountPercent,
        vatRate,
        note,
      ];
}
