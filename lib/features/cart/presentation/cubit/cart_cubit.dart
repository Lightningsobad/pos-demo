import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:demo_application/features/cart/domain/entities/cart_summary.dart';
import 'package:demo_application/features/cart/domain/repositories/cart_repository.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit managing POS cart items, line/order discounts, VAT, notes, and local draft persistence.
class CartCubit extends Cubit<CartState> {
  CartCubit({
    required this._repository,
    String? defaultStaffName,
  }) : super(
          CartState(
            staffName: (defaultStaffName ?? '').trim().isNotEmpty
                ? defaultStaffName!.trim()
                : AppSettings.sampleStaffNames.first,
            paymentMethod: CartDraft.defaultPaymentMethod,
          ),
        );

  static const List<String> paymentMethods = CartDraft.paymentMethods;

  final CartRepository _repository;

  /// Loads any locally persisted draft cart and recalculates [CartSummary].
  Future<void> loadDraftCart() async {
    emit(state.copyWith(status: CartStatus.loading, clearError: true));
    try {
      final draft = await _repository.loadDraft();
      if (isClosed) return;

      final resolvedStaff = draft.staffName.trim().isNotEmpty
          ? draft.staffName.trim()
          : state.staffName;
      final summary = CartSummary.fromItems(
        draft.items,
        orderDiscountPercent: draft.orderDiscountPercent,
      );

      emit(
        state.copyWith(
          status: CartStatus.ready,
          items: List.unmodifiable(draft.items),
          orderDiscountPercent: draft.orderDiscountPercent,
          staffName: resolvedStaff,
          paymentMethod: draft.paymentMethod,
          summary: summary,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      _emitError('Không thể tải giỏ hàng nháp: $error', status: CartStatus.ready);
    }
  }

  /// Adds [product] or increments its quantity by 1 if already present.
  Future<void> addProduct(Product product) async {
    if (!product.price.isFinite ||
        product.price < 0 ||
        !_isValidPercent(product.vatRate)) {
      _emitError('Thông tin giá hoặc VAT của sản phẩm không hợp lệ');
      return;
    }

    final updatedItems = List<CartItem>.of(state.items);
    final existingIndex =
        updatedItems.indexWhere((item) => item.productId == product.id);
    if (existingIndex >= 0) {
      final current = updatedItems[existingIndex];
      updatedItems[existingIndex] =
          current.copyWith(quantity: current.quantity + 1);
    } else {
      updatedItems.add(CartItem.fromProduct(product));
    }

    await _commitItemsUpdate(updatedItems);
  }

  /// Updates quantity, discount %, VAT %, or note of an existing cart line.
  Future<void> updateItem(
    int productId, {
    double? quantity,
    double? discountPercent,
    double? vatRate,
    String? note,
  }) async {
    final index = state.items.indexWhere((item) => item.productId == productId);
    if (index < 0) {
      _emitError('Không tìm thấy sản phẩm trong giỏ hàng');
      return;
    }

    if (quantity != null && !_isValidQuantity(quantity)) {
      _emitError('Số lượng phải lớn hơn 0');
      return;
    }
    if (discountPercent != null && !_isValidPercent(discountPercent)) {
      _emitError('Chiết khấu sản phẩm phải trong khoảng 0% - 100%');
      return;
    }
    if (vatRate != null && !_isValidPercent(vatRate)) {
      _emitError('Thuế VAT phải trong khoảng 0% - 100%');
      return;
    }

    final updatedItems = List<CartItem>.of(state.items);
    updatedItems[index] = updatedItems[index].copyWith(
      quantity: quantity,
      discountPercent: discountPercent,
      vatRate: vatRate,
      note: note,
    );

    await _commitItemsUpdate(updatedItems);
  }

  /// Removes a line item by [productId].
  Future<void> removeItem(int productId) async {
    final updatedItems = state.items
        .where((item) => item.productId != productId)
        .toList(growable: false);
    if (updatedItems.length == state.items.length) return;
    await _commitItemsUpdate(updatedItems);
  }

  /// Sets the whole-order discount percentage within `[0, 100]`.
  Future<void> setOrderDiscountPercent(double percent) async {
    if (!_isValidPercent(percent)) {
      _emitError('Giảm giá toàn đơn phải trong khoảng 0% - 100%');
      return;
    }

    final summary = CartSummary.fromItems(
      state.items,
      orderDiscountPercent: percent,
    );
    final nextState = state.copyWith(
      status: CartStatus.ready,
      orderDiscountPercent: percent,
      summary: summary,
      clearError: true,
    );
    emit(nextState);
    await _persistDraft(nextState);
  }

  /// Updates the active cashier/staff name.
  Future<void> setStaffName(String staffName) async {
    final trimmed = staffName.trim();
    if (trimmed.isEmpty) {
      _emitError('Tên nhân viên không được để trống');
      return;
    }

    final nextState = state.copyWith(
      status: CartStatus.ready,
      staffName: trimmed,
      clearError: true,
    );
    emit(nextState);
    await _persistDraft(nextState);
  }

  /// Updates the selected payment method from [paymentMethods].
  Future<void> setPaymentMethod(String paymentMethod) async {
    if (!paymentMethods.contains(paymentMethod)) {
      _emitError('Hình thức thanh toán không hợp lệ');
      return;
    }

    final nextState = state.copyWith(
      status: CartStatus.ready,
      paymentMethod: paymentMethod,
      clearError: true,
    );
    emit(nextState);
    await _persistDraft(nextState);
  }

  /// Clears all items and order discount while preserving cashier/payment defaults.
  Future<void> clearCart() async {
    emit(
      state.copyWith(
        status: CartStatus.ready,
        items: const [],
        orderDiscountPercent: 0,
        summary: const CartSummary(),
        clearError: true,
      ),
    );
    try {
      await _repository.clearDraft();
    } catch (error) {
      if (isClosed) return;
      _emitError('Không thể xóa giỏ hàng nháp: $error');
    }
  }

  Future<void> _commitItemsUpdate(List<CartItem> items) async {
    final immutableItems = List<CartItem>.unmodifiable(items);
    final summary = CartSummary.fromItems(
      immutableItems,
      orderDiscountPercent: state.orderDiscountPercent,
    );
    final nextState = state.copyWith(
      status: CartStatus.ready,
      items: immutableItems,
      summary: summary,
      clearError: true,
    );
    emit(nextState);
    await _persistDraft(nextState);
  }

  Future<void> _persistDraft(CartState targetState) async {
    try {
      await _repository.saveDraft(
        CartDraft(
          items: targetState.items,
          orderDiscountPercent: targetState.orderDiscountPercent,
          staffName: targetState.staffName,
          paymentMethod: targetState.paymentMethod,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      _emitError('Không thể lưu giỏ hàng nháp: $error');
    }
  }

  void _emitError(String message, {CartStatus? status}) {
    emit(
      state.copyWith(
        status: status,
        errorMessage: message,
        errorNonce: state.errorNonce + 1,
      ),
    );
  }

  static bool _isValidQuantity(double value) => value.isFinite && value > 0;

  static bool _isValidPercent(double value) =>
      value.isFinite && value >= 0 && value <= 100;
}
