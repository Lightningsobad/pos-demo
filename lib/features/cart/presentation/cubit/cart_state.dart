import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:demo_application/features/cart/domain/entities/cart_summary.dart';
import 'package:demo_application/features/cart/domain/repositories/cart_repository.dart';
import 'package:equatable/equatable.dart';

/// Lifecycle status for loading the POS cart draft.
enum CartStatus { initial, loading, ready }

/// Immutable state managed by [CartCubit].
class CartState extends Equatable {
  const CartState({
    this.status = CartStatus.initial,
    this.items = const [],
    this.orderDiscountPercent = 0,
    this.staffName = '',
    this.paymentMethod = CartDraft.defaultPaymentMethod,
    this.summary = const CartSummary(),
    this.errorMessage,
    this.errorNonce = 0,
  });

  final CartStatus status;
  final List<CartItem> items;
  final double orderDiscountPercent;
  final String staffName;
  final String paymentMethod;
  final CartSummary summary;
  final String? errorMessage;
  final int errorNonce;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  CartState copyWith({
    CartStatus? status,
    List<CartItem>? items,
    double? orderDiscountPercent,
    String? staffName,
    String? paymentMethod,
    CartSummary? summary,
    String? errorMessage,
    int? errorNonce,
    bool clearError = false,
  }) {
    return CartState(
      status: status ?? this.status,
      items: items ?? this.items,
      orderDiscountPercent: orderDiscountPercent ?? this.orderDiscountPercent,
      staffName: staffName ?? this.staffName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      summary: summary ?? this.summary,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorNonce: errorNonce ?? this.errorNonce,
    );
  }

  @override
  List<Object?> get props => [
        status,
        items,
        orderDiscountPercent,
        staffName,
        paymentMethod,
        summary,
        errorMessage,
        errorNonce,
      ];
}
