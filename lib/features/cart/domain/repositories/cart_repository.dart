import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:equatable/equatable.dart';

/// Serializable draft cart snapshot persisted locally between sessions.
class CartDraft extends Equatable {
  const CartDraft({
    this.items = const [],
    this.orderDiscountPercent = 0,
    this.staffName = '',
    this.paymentMethod = defaultPaymentMethod,
  });

  static const List<String> paymentMethods = [
    'Tiền mặt',
    'Chuyển khoản',
    'Quẹt thẻ',
    'Ví điện tử',
  ];

  static const String defaultPaymentMethod = 'Tiền mặt';

  final List<CartItem> items;
  final double orderDiscountPercent;
  final String staffName;
  final String paymentMethod;

  @override
  List<Object?> get props => [
        items,
        orderDiscountPercent,
        staffName,
        paymentMethod,
      ];
}

/// Local draft persistence contract for the POS cart.
abstract interface class CartRepository {
  Future<CartDraft> loadDraft();

  Future<void> saveDraft(CartDraft draft);

  Future<void> clearDraft();
}
