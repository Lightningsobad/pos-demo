import 'dart:convert';

import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:demo_application/features/cart/domain/repositories/cart_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local [SharedPreferences] persistence for draft POS carts.
class CartLocalDataSource {
  CartLocalDataSource({required this._prefs});

  static const String storageKey = 'pos_cart_draft_v1';

  final SharedPreferences _prefs;

  Future<CartDraft> loadDraft() async {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const CartDraft();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const CartDraft();
      }
      return _fromJson(decoded);
    } on FormatException {
      return const CartDraft();
    }
  }

  Future<void> saveDraft(CartDraft draft) async {
    final encoded = jsonEncode(_toJson(draft));
    final saved = await _prefs.setString(storageKey, encoded);
    if (!saved) {
      throw StateError('Không thể lưu giỏ hàng nháp vào bộ nhớ cục bộ');
    }
  }

  Future<void> clearDraft() async {
    await _prefs.remove(storageKey);
  }

  static Map<String, dynamic> _toJson(CartDraft draft) {
    return {
      'orderDiscountPercent': draft.orderDiscountPercent,
      'staffName': draft.staffName,
      'paymentMethod': draft.paymentMethod,
      'items': draft.items
          .map(
            (item) => {
              'productId': item.productId,
              'sku': item.sku,
              'name': item.name,
              'unit': item.unit,
              'unitPrice': item.unitPrice,
              'quantity': item.quantity,
              'discountPercent': item.discountPercent,
              'vatRate': item.vatRate,
              'note': item.note,
            },
          )
          .toList(growable: false),
    };
  }

  static CartDraft _fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <CartItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          final parsed = _itemFromJson(entry);
          if (parsed != null) items.add(parsed);
        }
      }
    }

    final orderDiscountPercent = _percentOr(json['orderDiscountPercent'], 0);
    final rawStaff = json['staffName'];
    final staffName = rawStaff is String ? rawStaff.trim() : '';
    final rawPayment = json['paymentMethod'];
    final paymentMethod =
        rawPayment is String && CartDraft.paymentMethods.contains(rawPayment)
            ? rawPayment
            : CartDraft.defaultPaymentMethod;

    return CartDraft(
      items: List.unmodifiable(items),
      orderDiscountPercent: orderDiscountPercent,
      staffName: staffName,
      paymentMethod: paymentMethod,
    );
  }

  static CartItem? _itemFromJson(Map<String, dynamic> json) {
    final productId = json['productId'];
    final sku = json['sku'];
    final name = json['name'];
    final unit = json['unit'];
    final unitPrice = _finiteDouble(json['unitPrice']);
    final quantity = _finiteDouble(json['quantity']);
    final discountPercent = _finiteDouble(json['discountPercent']) ?? 0;
    final vatRate = _finiteDouble(json['vatRate']);
    final note = json['note'];

    if (productId is! int ||
        sku is! String ||
        name is! String ||
        unit is! String ||
        unitPrice == null ||
        unitPrice < 0 ||
        quantity == null ||
        quantity <= 0 ||
        discountPercent < 0 ||
        discountPercent > 100 ||
        vatRate == null ||
        vatRate < 0 ||
        vatRate > 100) {
      return null;
    }

    return CartItem(
      productId: productId,
      sku: sku,
      name: name,
      unit: unit,
      unitPrice: unitPrice,
      quantity: quantity,
      discountPercent: discountPercent,
      vatRate: vatRate,
      note: note is String ? note : '',
    );
  }

  static double? _finiteDouble(Object? value) {
    if (value is num) {
      final result = value.toDouble();
      return result.isFinite ? result : null;
    }
    return null;
  }

  static double _percentOr(Object? value, double fallback) {
    final parsed = _finiteDouble(value);
    if (parsed == null || parsed < 0 || parsed > 100) {
      return fallback;
    }
    return parsed;
  }
}
