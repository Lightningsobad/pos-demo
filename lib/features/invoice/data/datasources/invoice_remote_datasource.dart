import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';

/// Remote HTTP datasource for `/api/orders`.
class InvoiceRemoteDatasource {
  InvoiceRemoteDatasource({required this._dioClient});

  final DioClient _dioClient;

  /// Submits a new POS order to `POST /api/orders` and returns the created invoice.
  Future<Invoice> createOrder(CreateOrderRequest request) async {
    final response = await _dioClient.dio.post<dynamic>(
      '/api/orders',
      data: request.toJson(),
    );
    return _parseInvoice(_requireMap(response.data, 'POST /api/orders'));
  }

  /// Fetches recent orders from `GET /api/orders?limit=...`.
  Future<List<Invoice>> fetchOrders({int limit = 20}) async {
    final response = await _dioClient.dio.get<dynamic>(
      '/api/orders',
      queryParameters: <String, dynamic>{'limit': limit},
    );
    final payload = _requireMap(response.data, 'GET /api/orders');
    final rawItems = payload['items'];
    if (rawItems is! List) {
      throw const FormatException('GET /api/orders missing items list');
    }
    return rawItems
        .map(
          (entry) => _parseInvoice(
            _requireMap(entry, 'GET /api/orders item'),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _requireMap(dynamic data, String context) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    throw FormatException('Unexpected response format for $context');
  }

  static Invoice _parseInvoice(Map<String, dynamic> json) {
    final storeJson = _requireMap(json['store'], 'invoice.store');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('invoice.items must be a list');
    }

    return Invoice(
      id: (json['id'] as num).toInt(),
      orderCode: json['orderCode'] as String,
      staffName: json['staffName'] as String,
      paymentMethod: json['paymentMethod'] as String,
      subtotal: (json['subtotal'] as num).toDouble(),
      discountPercent: (json['discountPercent'] as num).toDouble(),
      discountAmount: (json['discountAmount'] as num).toDouble(),
      totalPayable: (json['totalPayable'] as num).toDouble(),
      store: InvoiceStore(
        name: storeJson['name'] as String,
        phone: (storeJson['phone'] as String?) ?? '',
        address: (storeJson['address'] as String?) ?? '',
        logoUrl: storeJson['logoUrl'] as String?,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      items: rawItems
          .map(
            (entry) => _parseInvoiceItem(
              _requireMap(entry, 'invoice.items[]'),
            ),
          )
          .toList(growable: false),
    );
  }

  static InvoiceItem _parseInvoiceItem(Map<String, dynamic> json) {
    return InvoiceItem(
      productId: (json['productId'] as num).toInt(),
      sku: json['sku'] as String,
      name: json['name'] as String,
      unit: json['unit'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      discountPercent: (json['discountPercent'] as num).toDouble(),
      discountAmount: (json['discountAmount'] as num).toDouble(),
      vatRate: (json['vatRate'] as num).toDouble(),
      vatAmount: (json['vatAmount'] as num).toDouble(),
      lineTotal: (json['lineTotal'] as num).toDouble(),
      note: (json['note'] as String?) ?? '',
    );
  }
}
