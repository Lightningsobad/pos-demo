import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:equatable/equatable.dart';

/// Store metadata snapshot stored on an issued invoice.
class InvoiceStore extends Equatable {
  const InvoiceStore({
    required this.name,
    required this.phone,
    required this.address,
    this.logoUrl,
  });

  factory InvoiceStore.fromStoreConfig(StoreConfig store) {
    final trimmedLogo = store.logoUrl.trim();
    return InvoiceStore(
      name: store.name.trim(),
      phone: store.phone.trim(),
      address: store.address.trim(),
      logoUrl: trimmedLogo.isEmpty ? null : trimmedLogo,
    );
  }

  final String name;
  final String phone;
  final String address;
  final String? logoUrl;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
    };
  }

  @override
  List<Object?> get props => [name, phone, address, logoUrl];
}

/// Persisted line item returned by the backend order API.
class InvoiceItem extends Equatable {
  const InvoiceItem({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discountPercent,
    required this.discountAmount,
    required this.vatRate,
    required this.vatAmount,
    required this.lineTotal,
    this.note = '',
  });

  final int productId;
  final String sku;
  final String name;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double discountPercent;
  final double discountAmount;
  final double vatRate;
  final double vatAmount;
  final double lineTotal;
  final String note;

  @override
  List<Object?> get props => [
        productId,
        sku,
        name,
        unit,
        quantity,
        unitPrice,
        discountPercent,
        discountAmount,
        vatRate,
        vatAmount,
        lineTotal,
        note,
      ];
}

/// Complete POS invoice returned from `POST /api/orders` and `GET /api/orders`.
class Invoice extends Equatable {
  const Invoice({
    required this.id,
    required this.orderCode,
    required this.staffName,
    required this.paymentMethod,
    required this.subtotal,
    required this.discountPercent,
    required this.discountAmount,
    required this.totalPayable,
    required this.store,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final String orderCode;
  final String staffName;
  final String paymentMethod;
  final double subtotal;
  final double discountPercent;
  final double discountAmount;
  final double totalPayable;
  final InvoiceStore store;
  final DateTime createdAt;
  final List<InvoiceItem> items;

  @override
  List<Object?> get props => [
        id,
        orderCode,
        staffName,
        paymentMethod,
        subtotal,
        discountPercent,
        discountAmount,
        totalPayable,
        store,
        createdAt,
        items,
      ];
}

/// Line item payload sent to `POST /api/orders`.
class CreateOrderItemInput extends Equatable {
  const CreateOrderItemInput({
    required this.productId,
    required this.quantity,
    required this.discountPercent,
    required this.vatRate,
    this.note = '',
  });

  final int productId;
  final double quantity;
  final double discountPercent;
  final double vatRate;
  final String note;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'productId': productId,
      'quantity': quantity,
      'discountPercent': discountPercent,
      'vatRate': vatRate,
      'note': note,
    };
  }

  @override
  List<Object?> get props => [productId, quantity, discountPercent, vatRate, note];
}

/// Request payload sent to `POST /api/orders`.
class CreateOrderRequest extends Equatable {
  const CreateOrderRequest({
    required this.staffName,
    required this.paymentMethod,
    required this.discountPercent,
    required this.store,
    required this.items,
  });

  factory CreateOrderRequest.fromCart({
    required CartState cart,
    required StoreConfig store,
  }) {
    return CreateOrderRequest(
      staffName: cart.staffName.trim(),
      paymentMethod: cart.paymentMethod.trim(),
      discountPercent: cart.orderDiscountPercent,
      store: InvoiceStore.fromStoreConfig(store),
      items: cart.items
          .map(
            (item) => CreateOrderItemInput(
              productId: item.productId,
              quantity: item.quantity,
              discountPercent: item.discountPercent,
              vatRate: item.vatRate,
              note: item.note,
            ),
          )
          .toList(growable: false),
    );
  }

  final String staffName;
  final String paymentMethod;
  final double discountPercent;
  final InvoiceStore store;
  final List<CreateOrderItemInput> items;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'staffName': staffName,
      'paymentMethod': paymentMethod,
      'discountPercent': discountPercent,
      'store': store.toJson(),
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }

  @override
  List<Object?> get props => [staffName, paymentMethod, discountPercent, store, items];
}
