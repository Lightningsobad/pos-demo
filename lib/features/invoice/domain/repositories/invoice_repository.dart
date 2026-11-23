import 'package:demo_application/features/invoice/domain/entities/invoice.dart';

/// Repository contract for submitting POS orders and loading order history.
abstract interface class InvoiceRepository {
  Future<Invoice> createOrder(CreateOrderRequest request);

  Future<List<Invoice>> fetchOrders({int limit = 20});
}
